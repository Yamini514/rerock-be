class App::Models::Builder < Sequel::Model
  EMAIL_REGEXP = /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/

  # BuilderForm.js deliberately does NOT duplicate these checks client-side
  # (matching models/area.rb's approach) — this validate is the single
  # source of truth for what's required/unique/well-formed, and
  # BuilderForm.js just relays whatever comes back from here onto the
  # matching field.
  def validate
    super
    validates_presence [:name, :slug, :headquarters, :description], message: 'is required'
    validates_unique :slug

    if name && (new? || column_changed?(:name))
      dup = self.class.where(Sequel.function(:lower, :name) => name.strip.downcase)
      dup = dup.exclude(id: id) unless new?
      errors.add(:name, 'already exists') if dup.first
    end

    if description.present? && description.strip.length < 10
      errors.add(:description, 'must be at least 10 characters')
    end

    current_year = Time.now.year
    unless established.is_a?(Integer) && established.between?(1900, current_year)
      errors.add(:established, "must be between 1900 and #{current_year}")
    end

    validates_format(EMAIL_REGEXP, :email, message: 'is not a valid email address') if email.present?
    errors.add(:phone, 'must be a 10-digit phone number') if phone.present? && phone.gsub(/\D/, '').length != 10
  end
end
