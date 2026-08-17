class App::Models::Property < Sequel::Model
  many_to_one :community
  many_to_one :builder
  many_to_one :area
  many_to_one :location
  many_to_one :property_type

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
  STATUSES = ['Available', 'Reserved', 'Sold', 'Under Construction', 'Ready To Move'].freeze
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
  # matching field. `location_id` stays excluded from presence
  # (migrations/0053 made it nullable on purpose — the admin form can no
  # longer set it at all); `slug` uniqueness mirrors the already-existing
  # DB unique index (migrations/0012). `builder_id`/`area_id` are still
  # required here even though services/properties.rb now derives them from
  # `community_id` before this validation ever runs — this stays as a
  # defense-in-depth guarantee that a Property can never end up saved
  # without them, regardless of caller.
  def validate
    super
    validates_presence [:title, :slug, :community_id, :builder_id, :area_id, :property_type_id, :price, :built_up_area, :status],
                        message: 'is required'
    validates_unique :slug

    errors.add(:status, "must be one of #{STATUSES.join(', ')}") if status.present? && !STATUSES.include?(status)
    errors.add(:furnishing, "must be one of #{FURNISHING_OPTIONS.join(', ')}") if furnishing.present? && !FURNISHING_OPTIONS.include?(furnishing)
    errors.add(:publish_status, "must be one of #{PUBLISH_STATUSES.join(', ')}") if publish_status.present? && !PUBLISH_STATUSES.include?(publish_status)

    if title && (new? || column_changed?(:title))
      dup = self.class.where(Sequel.function(:lower, :title) => title.strip.downcase)
      dup = dup.exclude(id: id) unless new?
      errors.add(:title, 'already exists') if dup.first
    end

    validates_operator(:>=, 0, :price) if price
    validates_operator(:>=, 0, :built_up_area) if built_up_area
    validates_operator(:>=, 0, :land_area) if land_area

    [:bedrooms, :bathrooms, :balconies].each do |field|
      value = send(field)
      errors.add(field, 'must be between 0 and 20') if value && !value.between?(0, 20)
    end

    errors.add(:images, 'add at least one photo') if images.nil? || images.empty?

    validate_configuration
  end

  private

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
end
