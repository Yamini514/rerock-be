class App::Models::Property < Sequel::Model
  many_to_one :community
  many_to_one :builder
  many_to_one :area
  many_to_one :property_type
  many_to_one :agent

  # Same additive-FK-alongside-the-slug sync as models/lead.rb's own
  # sync_agent_reference! (migrations/0088, CRM pass) — see that file's
  # comment for the full reasoning. `agent_slug` (migrations/0012) stays
  # the field PropertyForm.js's existing Advisor Select submits; `agent_id`
  # (migrations/0095) is kept in lockstep so a real FK exists to protect
  # against a stale/deleted Agent reference.
  def before_validation
    if new?
      if agent_id.present?
        self.agent_slug = App::Models::Agent[agent_id]&.slug
      elsif agent_slug.present?
        self.agent_id = App::Models::Agent.where(slug: agent_slug).first&.id
      end
    elsif column_changed?(:agent_id)
      self.agent_slug = agent_id.present? ? App::Models::Agent[agent_id]&.slug : nil
    elsif column_changed?(:agent_slug)
      self.agent_id = agent_slug.present? ? App::Models::Agent.where(slug: agent_slug).first&.id : nil
    end

    # `publish_status` is the single source of truth for the publishing
    # lifecycle (Draft/Scheduled/Published/Archived) — a brand-new Property
    # always starts as Draft. Column default of 'Draft' only covers a row
    # that never sets the column at all; PropertyForm.js's own progressive
    # "Save & Next" always sends `publish_status` in the payload (even
    # before the admin has ever opened the Publish tab, where it's still
    # "" from the unselected placeholder option), which would otherwise
    # overwrite that column default with a blank string instead of a real
    # lifecycle value.
    #
    # Deliberately NOT scoped to `new?` (was originally, which was the bug):
    # an admin editing an EXISTING property who opens the Publish tab and
    # explicitly re-selects the blank "Select Publish Status" placeholder
    # hits this exact same blank-string case, just on an update instead of a
    # create — and `publish_status` isn't in the required-fields list, so
    # nothing else caught it. Properties#list's own Active
    # ("Draft,Scheduled,Published") and Archived ("Archived") filters both
    # exclude an empty string, so that property vanished from *both* tabs
    # with no toggle left that could ever show it again — indistinguishable
    # from being deleted, even though the row was still sitting in the
    # database untouched.
    self.publish_status = 'Draft' if publish_status.blank?

    # `publish_at` only ever means something for Scheduled, so this
    # normalizes it to nil the instant any other status is chosen, the same
    # way PropertyForm.js's own `buildPayload` already does client-side.
    # Doing it here too (rather than trusting the client) closes the gap
    # for CSV import, duplication, and any other caller that builds a
    # Property payload directly.
    self.publish_at = nil if publish_status.present? && publish_status != 'Scheduled'

    super
  end

  # Mirrors PropertyForm.js's own option lists. `STATUSES` is presence-
  # required below (it lives on the same "basic" tab as title/community_id/
  # etc., which are already unconditionally required, so requiring it too
  # doesn't conflict with the form's progressive "Save & Next" saves).
  # `FURNISHING_OPTIONS`/`PUBLISH_STATUSES` are enum-checked but NOT
  # presence-required — both live on later tabs (Features/Publish) the
  # admin hasn't necessarily reached yet by the time an earlier tab's
  # "Save & Next" already persisted the row, and Furnishing is genuinely
  # not applicable to a Land/Plot property type at all (see
  # PropertyForm.js's own isLandType heuristic).
  STATUSES = ['Available', 'Reserved', 'Sold', 'Under Construction', 'Ready To Move', 'Unavailable'].freeze
  FURNISHING_OPTIONS = ['Unfurnished', 'Semi-Furnished', 'Fully Furnished'].freeze
  PUBLISH_STATUSES = ['Draft', 'Published', 'Archived', 'Scheduled'].freeze

  # RERA lives entirely on Community, not Property (migrations/0072/0073 —
  # the old per-property `rera` boolean was dropped as a duplicate of
  # Community's real rera_status/rera columns). Every frontend surface that
  # shows a property's RERA badge (site/agent/RAM/portal cards, the client
  # portal's property detail page) needs that status without each one
  # having to separately fetch and join against the communities list, so
  # it's merged onto the property response here — same "decorate to_pos
  # with one merged extra" convention as Agent#with_live_stats/
  # Client#with_status_history. `list`'s dataset eager-loads :community
  # (see services/properties.rb) so this doesn't N+1 per row.
  def to_pos
    super.merge('community_rera_status' => community&.rera_status)
  end

  # PropertyForm.js deliberately does NOT duplicate these checks
  # client-side (matching models/area.rb / models/builder.rb / models/
  # community.rb's approach) — this validate is the single source of
  # truth, and the form just relays whatever comes back from here onto the
  # matching field. `slug` uniqueness mirrors the already-existing
  # DB unique index (migrations/0012). `builder_id`/`area_id` are still
  # required here even though services/properties.rb now derives them from
  # `community_id` before this validation ever runs — this stays as a
  # defense-in-depth guarantee that a Property can never end up saved
  # without them, regardless of caller.
  def validate
    super
    # `agent_id` added so a property can never go live with no advisor
    # attached — public_agents.rb's directory only ever returns Active
    # agents, and the public property page's own "Your Advisor" card
    # silently disappears with no error when the lookup comes up empty
    # (an unassigned property, or one assigned to a non-Active agent, look
    # identical to a visitor). Requiring assignment here at least guarantees
    # the first case can't happen; the agent's own status is a separate
    # concern (Agents#update, not this model).
    validates_presence [:title, :slug, :community_id, :builder_id, :area_id, :property_type_id, :price, :built_up_area, :status, :agent_id],
                        message: 'is required'
    validates_unique :slug

    errors.add(:status, "must be one of #{STATUSES.join(', ')}") if status.present? && !STATUSES.include?(status)
    errors.add(:furnishing, "must be one of #{FURNISHING_OPTIONS.join(', ')}") if furnishing.present? && !FURNISHING_OPTIONS.include?(furnishing)
    errors.add(:publish_status, "must be one of #{PUBLISH_STATUSES.join(', ')}") if publish_status.present? && !PUBLISH_STATUSES.include?(publish_status)
    errors.add(:publish_at, 'is required when Publish Status is Scheduled') if publish_status == 'Scheduled' && publish_at.blank?
    errors.add(:publish_at, "can't be in the past") if publish_status == 'Scheduled' && publish_at.present? && publish_at < Time.now

    if title && (new? || column_changed?(:title))
      dup = self.class.where(Sequel.function(:lower, :title) => title.strip.downcase)
      dup = dup.exclude(id: id) unless new?
      errors.add(:title, 'already exists') if dup.first
    end

    validates_operator(:>=, 0, :price) if price
    validates_operator(:>=, 0, :built_up_area) if built_up_area
    validates_operator(:>=, 0, :land_area) if land_area
    validates_operator(:>=, 0, :offer_price) if offer_price

    # Had no relationship check to `price` at all before — an offer/discount
    # price that isn't actually lower than the base price isn't a real offer,
    # and the admin Property Detail page shows both side by side (Base
    # Price / Offer Price stats) where a higher "offer" would visibly make
    # no sense. Scoped to an actual change on either field so an existing
    # legacy row with an already-inconsistent pair doesn't suddenly start
    # failing on an unrelated edit.
    if offer_price.present? && price.present? && offer_price >= price && (new? || column_changed?(:price) || column_changed?(:offer_price))
      errors.add(:offer_price, 'must be less than the base Price')
    end

    [:bedrooms, :bathrooms, :balconies].each do |field|
      value = send(field)
      errors.add(field, 'must be between 0 and 20') if value && !value.between?(0, 20)
    end

    # Optional per-property override of the RAM commission rate
    # (migrations/0099) — see Deal#ensure_commission_for_closure!'s own
    # comment for the fallback chain this feeds into. Nil just means "use
    # the referring RAM's own default rate instead."
    errors.add(:commission_rate, 'must be between 0 and 100') if commission_rate && !commission_rate.between?(0, 100)

    errors.add(:images, 'add at least one photo') if images.nil? || images.empty?

    validate_configuration
    validate_amenity_and_tag_ids
    validate_property_type_not_archived
    validate_community_not_archived
  end

  private

  # `amenity_ids`/`tag_ids` are plain Postgres integer[] columns, not join
  # tables (see migrations/0012's own comment on why — Base#create/#update's
  # generic `data_for(:save)` + `set_fields` has no support for many-to-many
  # association setters, so a join table would need bespoke add/remove
  # actions for no relational-integrity benefit at this scale), which means
  # nothing at the DB level stops a stale/typo'd id from silently sitting in
  # either array. This is the real, unbypassable guard underneath
  # AmenitiesLibraryTab's/PropertyTagsLibraryTab's own "in use" delete guard
  # (services/amenities.rb, services/property_tags.rb) — same "typo
  # shouldn't silently create an orphaned assignment" reasoning as
  # Community#validate's own builder_id/area_id existence checks. Scoped to
  # `new? || column_changed?(...)` so an unrelated edit to an already-existing
  # property with a legacy bad id doesn't suddenly start failing.
  def validate_amenity_and_tag_ids
    # `amenity_ids`/`tag_ids` are Sequel::Postgres::PGArray at this point
    # (the pg_array extension typecasts each integer[] column into one on
    # load/assignment), not a plain Ruby Array — passing either straight
    # into `where(id: ...)` makes Sequel build a single
    # `"id" = ARRAY[...]::integer[]` equality comparison instead of an
    # `IN (...)` list, which Postgres rejects (`integer = integer[]` has no
    # such operator). `.to_a` converts each to a genuine plain Array first,
    # so this becomes the intended IN-list query — same fix as
    # models/community.rb's own validate_amenity_ids.
    if amenity_ids.present? && (new? || column_changed?(:amenity_ids))
      ids = amenity_ids.to_a
      valid_ids = App::Models::Amenity.where(id: ids).select_map(:id)
      invalid_ids = ids - valid_ids
      errors.add(:amenity_ids, "references amenities that don't exist: #{invalid_ids.join(', ')}") if invalid_ids.any?
    end

    if tag_ids.present? && (new? || column_changed?(:tag_ids))
      ids = tag_ids.to_a
      valid_ids = App::Models::PropertyTag.where(id: ids).select_map(:id)
      invalid_ids = ids - valid_ids
      errors.add(:tag_ids, "references property tags that don't exist: #{invalid_ids.join(', ')}") if invalid_ids.any?
    end
  end

  # Configuration is never a fixed, hardcoded enum (unlike Community's
  # CONSTRUCTION_STATUSES/RERA_STATUSES) — it must be one of the selected
  # Community's own `unit_types` (see models/community.rb), so
  # PropertyForm.js can only ever offer options that the Community actually
  # configured; nothing here is allowed to fall back to a default value.
  # Kept out of the plain `validates_presence` list above because a blank
  # value means one of two very different things to tell the admin apart:
  # an ordinary empty field, or a Community that was never given any Unit
  # Types to begin with — the two need different messages.
  def validate_configuration
    unless community_id
      errors.add(:configuration, 'is required') if configuration.blank?
      return
    end

    community = App::Models::Community[community_id]
    unless community
      errors.add(:community_id, 'must reference an existing Community')
      return
    end

    if community.unit_types.blank?
      errors.add(:configuration, "is required, but the selected Community has no Unit Types configured — add Unit Types to the Community first")
    elsif configuration.blank?
      errors.add(:configuration, 'is required')
    elsif !community.unit_types.include?(configuration)
      errors.add(:configuration, "must be one of the selected Community's Unit Types: #{community.unit_types.join(', ')}")
    end
  end

  # Archived Property Types are retired from the taxonomy (still kept as a
  # real row so existing Properties don't lose their reference — see
  # models/property_type.rb), so a brand-new assignment to one is rejected
  # here the same way models/community.rb rejects a builder_id/area_id that
  # doesn't exist. Scoped to `new? || column_changed?(:property_type_id)` —
  # same convention as validate_amenity_and_tag_ids above — so an existing
  # Property already on a since-archived type keeps saving normally through
  # every other tab/action (price edits, status changes, archive/restore,
  # etc.) without this suddenly blocking it.
  def validate_property_type_not_archived
    return unless property_type_id && (new? || column_changed?(:property_type_id))

    property_type = App::Models::PropertyType[property_type_id]
    errors.add(:property_type_id, 'must reference an existing Property Type') if property_type.nil?
    errors.add(:property_type_id, 'is archived and can no longer be assigned to a Property') if property_type&.archived
  end

  # Same reasoning as validate_property_type_not_archived above, for the
  # Community side of a Property — an archived Community can't accept a
  # brand-new Property either. Existence of the Community itself is already
  # checked by validate_configuration above; this only adds the archived
  # check, scoped identically so an existing Property on a since-archived
  # Community keeps saving normally through every other tab/action.
  def validate_community_not_archived
    return unless community_id && (new? || column_changed?(:community_id))

    community = App::Models::Community[community_id]
    errors.add(:community_id, 'is archived and can no longer accept new Properties') if community&.archived
  end
end
