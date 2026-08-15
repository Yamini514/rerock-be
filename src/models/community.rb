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
    end

    errors.add(:status, "must be one of #{CONSTRUCTION_STATUSES.join(', ')}") if status.present? && !CONSTRUCTION_STATUSES.include?(status)
    errors.add(:rera_status, "must be one of #{RERA_STATUSES.join(', ')}") if rera_status.present? && !RERA_STATUSES.include?(rera_status)
    errors.add(:rera, 'is required when RERA Status is Approved') if rera_status == 'Approved' && rera.blank?

    errors.add(:builder_id, 'must reference an existing Builder') if builder_id && App::Models::Builder[builder_id].nil?
    errors.add(:area_id, 'must reference an existing Area') if area_id && App::Models::Area[area_id].nil?

    errors.add(:total_units, 'must be greater than 0') if total_units && total_units <= 0
    errors.add(:price_min, 'must be greater than 0') if price_min && price_min <= 0
    validates_operator(:>=, 0, :price_max) if price_max
    if price_min && price_max && price_max < price_min && (new? || column_changed?(:price_min) || column_changed?(:price_max))
      errors.add(:price_max, 'must be greater than or equal to price_min')
    end

    errors.add(:investment_score, 'must be between 0 and 100') if investment_score && !investment_score.between?(0, 100)

    validate_floor_plans
  end

  private

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
