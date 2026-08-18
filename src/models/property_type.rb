class App::Models::PropertyType < Sequel::Model
  NAME_MAX_LENGTH = 50
  DESCRIPTION_MIN_LENGTH = 10
  DESCRIPTION_MAX_LENGTH = 300

  # PropertyTypeForm.js's own validate() mirrors these exact same rules
  # client-side for instant feedback, but this is the real source of
  # truth — a direct API call bypasses the form entirely. Length checks are
  # scoped to `new? || column_changed?(...)` (same convention as
  # Client#validate/Agent#validate) so a legacy row whose name/description
  # predates these limits can still go through an unrelated partial update
  # (Archive/Restore, reordering) without suddenly failing on a field
  # nobody touched.
  def validate
    super
    validates_presence [:name], message: 'is required'

    if name.present? && (new? || column_changed?(:name))
      errors.add(:name, 'must be at least 2 characters') if name.strip.length < 2
      errors.add(:name, "must be #{NAME_MAX_LENGTH} characters or less") if name.length > NAME_MAX_LENGTH
    end

    if new? || column_changed?(:description)
      errors.add(:description, 'is required') if description.blank?
      if description.present?
        errors.add(:description, "must be at least #{DESCRIPTION_MIN_LENGTH} characters") if description.strip.length < DESCRIPTION_MIN_LENGTH
        errors.add(:description, "must be #{DESCRIPTION_MAX_LENGTH} characters or less") if description.length > DESCRIPTION_MAX_LENGTH
      end
    end
  end
end
