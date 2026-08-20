class App::Models::Community < Sequel::Model
  many_to_one :builder
  many_to_one :area
  many_to_one :location

  # Fixed, small enums (same category as Builder's Active/Inactive `status`)
  # — not a dynamic admin-managed resource like Builder/Area/Amenity, so
  # CommunityForm.js is allowed to hold its own copy of these for the
  # dropdown options, same precedent as BuilderForm.js's STATUSES.
  CONSTRUCTION_STATUSES = ['Under Construction', 'Ready To Move', 'Completed'].freeze
  RERA_STATUSES = ['Approved', 'Pending', 'Not Registered'].freeze

  NAME_MAX_LENGTH = 100
  TAGLINE_MAX_LENGTH = 150
  RERA_MAX_LENGTH = 50
  POSSESSION_MAX_LENGTH = 50
  OVERVIEW_MAX_LENGTH = 2000
  MASTER_PLAN_MAX_LENGTH = 2000

  # CommunityForm.js deliberately does NOT duplicate these checks
  # client-side (matching models/area.rb / models/builder.rb's approach) —
  # this validate is the single source of truth, and CommunityForm.js just
  # relays whatever comes back from here onto the matching field.
  # `location_id` is deliberately excluded from presence (migrations/0053
  # made it nullable on purpose); `slug` uniqueness mirrors the
  # already-existing DB unique index (migrations/0011).
  def validate
    super
    validates_presence [:name, :slug, :builder_id, :area_id, :status, :rera_status, :total_units, :price_min],
                        message: 'is required'
    validates_unique :slug

    if name && (new? || column_changed?(:name))
      dup = self.class.where(Sequel.function(:lower, :name) => name.strip.downcase)
      dup = dup.exclude(id: id) unless new?
      errors.add(:name, 'already exists') if dup.first

      errors.add(:name, 'must be at least 2 characters') if name.strip.length < 2
      errors.add(:name, "must be #{NAME_MAX_LENGTH} characters or less") if name.length > NAME_MAX_LENGTH
    end

    # Length checks below are scoped to `new? || column_changed?(...)` (same
    # convention as models/property_type.rb/area.rb) rather than firing on
    # every save — Communities#bulk_price_update and the admin list page's
    # Archive/Restore/Featured-toggle actions all send partial payloads that
    # never touch these text fields, so a legacy row whose tagline/overview/
    # etc. predates these limits must still be able to go through one of
    # those unrelated actions without suddenly failing.
    if tagline.present? && (new? || column_changed?(:tagline))
      errors.add(:tagline, "must be #{TAGLINE_MAX_LENGTH} characters or less") if tagline.length > TAGLINE_MAX_LENGTH
    end

    if overview.present? && (new? || column_changed?(:overview))
      errors.add(:overview, "must be #{OVERVIEW_MAX_LENGTH} characters or less") if overview.length > OVERVIEW_MAX_LENGTH
    end

    if master_plan.present? && (new? || column_changed?(:master_plan))
      errors.add(:master_plan, "must be #{MASTER_PLAN_MAX_LENGTH} characters or less") if master_plan.length > MASTER_PLAN_MAX_LENGTH
    end

    if possession.present? && (new? || column_changed?(:possession))
      errors.add(:possession, "must be #{POSSESSION_MAX_LENGTH} characters or less") if possession.length > POSSESSION_MAX_LENGTH
    end

    errors.add(:status, "must be one of #{CONSTRUCTION_STATUSES.join(', ')}") if status.present? && !CONSTRUCTION_STATUSES.include?(status)
    errors.add(:rera_status, "must be one of #{RERA_STATUSES.join(', ')}") if rera_status.present? && !RERA_STATUSES.include?(rera_status)
    errors.add(:rera, 'is required when RERA Status is Approved') if rera_status == 'Approved' && rera.blank?
    # A registration number only means something once RERA has actually
    # approved it — nothing stopped one from being typed in while status sat
    # at Pending/Not Registered. Scoped to an actual change on either field
    # (same convention as the length/cross-field checks throughout this
    # method) so a legacy row saved before this existed doesn't suddenly fail
    # on an unrelated edit (e.g. Communities#bulk_price_update).
    if rera_status != 'Approved' && rera.present? && (new? || column_changed?(:rera) || column_changed?(:rera_status))
      errors.add(:rera, 'can only be set once RERA Status is Approved')
    end
    if rera.present? && (new? || column_changed?(:rera))
      errors.add(:rera, "must be #{RERA_MAX_LENGTH} characters or less") if rera.length > RERA_MAX_LENGTH
    end

    validate_builder
    errors.add(:area_id, 'must reference an existing Area') if area_id && App::Models::Area[area_id].nil?

    errors.add(:total_units, 'must be greater than 0') if total_units && total_units <= 0
    errors.add(:available_units, 'cannot be negative') if available_units && available_units < 0
    if total_units && available_units && available_units > total_units && (new? || column_changed?(:total_units) || column_changed?(:available_units))
      errors.add(:available_units, 'cannot be greater than Total Units')
    end
    # Plain Postgres text[] (migrations/0011), not a presence-checkable
    # scalar column — `validates_presence` above wouldn't catch an empty
    # array, so this is checked the same way property.rb's own `images`
    # array is. Every Property's own Configuration is validated against
    # this list (models/property.rb#validate_configuration), so a Community
    # with none configured would otherwise be impossible to list any real
    # unit against.
    errors.add(:unit_types, 'add at least one Unit Type') if unit_types.nil? || unit_types.empty?
    errors.add(:price_min, 'must be greater than 0') if price_min && price_min <= 0
    validates_operator(:>=, 0, :price_max) if price_max
    if price_min && price_max && price_max < price_min && (new? || column_changed?(:price_min) || column_changed?(:price_max))
      errors.add(:price_max, 'must be greater than or equal to price_min')
    end

    errors.add(:investment_score, 'must be between 0 and 100') if investment_score && !investment_score.between?(0, 100)
    # YoY price appreciation can go negative (a real downturn), so this
    # isn't clamped to 0 like investment_score above — just wide enough to
    # catch an obvious typo (e.g. "9900" meant to be "9.9") while allowing
    # any real-world swing.
    errors.add(:growth_pct, 'must be between -100 and 100') if growth_pct && !growth_pct.between?(-100, 100)

    validate_floor_plans
    validate_amenity_ids
    validate_archive_guard
  end

  private

  # An Inactive Builder is being retired from active use (see
  # models/builder.rb's own validate_status_change_guard) — scoped to
  # `new? || column_changed?(:builder_id)` so an existing Community whose
  # Builder later goes Inactive keeps saving normally through every other
  # tab/action (pricing, amenities, archive/restore, etc.) without this
  # suddenly blocking it, same convention as models/property.rb's
  # validate_property_type_not_archived/validate_community_not_archived.
  def validate_builder
    return unless builder_id

    builder = App::Models::Builder[builder_id]
    errors.add(:builder_id, 'must reference an existing Builder') if builder.nil?
    if builder && builder.status != 'Active' && (new? || column_changed?(:builder_id))
      errors.add(:builder_id, 'is Inactive and cannot be assigned to a Community')
    end
  end

  # Mirrors Base#delete's own FK-violation guard, but for the Archive action
  # (a plain `archived` column flip, not a real delete) — a Community with
  # live Properties still on it can't be quietly hidden out from under them.
  # `publish_status != 'Archived'` here matches services/communities.rb#
  # community_stats' own `property_count` (excludes already-archived
  # Properties via the same single source of truth, see
  # models/property.rb) — the same count the admin UI already shows before
  # this guard ever fires.
  def validate_archive_guard
    return unless archived && column_changed?(:archived)

    has_properties = App::Models::Property.where(community_id: id).exclude(publish_status: 'Archived').count > 0
    if has_properties
      errors.add(:archived, 'cannot be changed while Properties are still assigned to this Community — reassign or archive them first')
    end
  end

  # Same reasoning as models/property.rb's own validate_amenity_and_tag_ids
  # (which this predates conceptually — `amenity_ids` here is the original
  # plain Postgres integer[] column, migrations/0011) — a stale/typo'd id
  # can't trigger a DB-level FK violation since there's no join table, so
  # this closes that gap at the app level instead, same "typo shouldn't
  # silently create an orphaned assignment" convention as this model's own
  # builder_id/area_id existence checks above.
  def validate_amenity_ids
    return unless amenity_ids.present? && (new? || column_changed?(:amenity_ids))

    # `amenity_ids` is a Sequel::Postgres::PGArray at this point (the pg_array
    # extension typecasts the integer[] column into one on load/assignment),
    # not a plain Ruby Array — passing it straight into `where(id: ...)`
    # makes Sequel build a single `"id" = ARRAY[...]::integer[]` equality
    # comparison instead of an `IN (...)` list, which Postgres rejects
    # (`integer = integer[]` has no such operator). `.to_a` converts it to a
    # genuine plain Array first, so this becomes the intended IN-list query.
    ids = amenity_ids.to_a
    valid_ids = App::Models::Amenity.where(id: ids).select_map(:id)
    invalid_ids = ids - valid_ids
    errors.add(:amenity_ids, "references amenities that don't exist: #{invalid_ids.join(', ')}") if invalid_ids.any?
  end

  # `floor_plans` (migrations/0077) is a project-wide "explore by
  # configuration" gallery, distinct from Property#floor_plans (a single
  # listed unit's plan, unvalidated). Its `configuration` must be one of
  # this same community's own `unit_types` — identical convention to
  # Property#configuration's validation against the parent Community (see
  # models/property.rb#validate_configuration) — so the admin UI can never
  # offer/save a configuration the community hasn't actually declared.
  def validate_floor_plans
    return if floor_plans.blank?

    floor_plans.each_with_index do |fp, i|
      configuration = fp['configuration'] || fp[:configuration]
      next if configuration.present? && (unit_types || []).include?(configuration)

      if unit_types.blank?
        errors.add(:floor_plans, "row #{i + 1}: configuration requires Unit Types to be set on this Community first")
      else
        errors.add(:floor_plans, "row #{i + 1}: configuration must be one of this Community's Unit Types: #{unit_types.join(', ')}")
      end
    end
  end
end
