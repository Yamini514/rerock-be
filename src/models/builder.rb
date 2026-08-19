class App::Models::Builder < Sequel::Model
  EMAIL_REGEXP = /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/

  # Loose enough to accept "example.com", "www.example.com", or a full
  # "https://example.com/path" — this is a plain String column with no
  # format check at all today, just like `sqft_delivered`/`name`/
  # `headquarters`/`headline`/`description` were before their own length
  # checks were added above.
  WEBSITE_REGEXP = /\A(https?:\/\/)?([\w-]+\.)+[a-z]{2,}([\/?#]\S*)?\z/i

  NAME_MAX_LENGTH = 100
  HEADQUARTERS_MAX_LENGTH = 100
  HEADLINE_MAX_LENGTH = 150
  DESCRIPTION_MIN_LENGTH = 10
  DESCRIPTION_MAX_LENGTH = 1000
  SQFT_DELIVERED_MAX_LENGTH = 50
  WEBSITE_MAX_LENGTH = 255

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

    if name.present?
      errors.add(:name, 'must be at least 2 characters') if name.strip.length < 2
      errors.add(:name, "must be #{NAME_MAX_LENGTH} characters or less") if name.length > NAME_MAX_LENGTH
    end

    errors.add(:headquarters, "must be #{HEADQUARTERS_MAX_LENGTH} characters or less") if headquarters && headquarters.length > HEADQUARTERS_MAX_LENGTH
    errors.add(:headline, "must be #{HEADLINE_MAX_LENGTH} characters or less") if headline && headline.length > HEADLINE_MAX_LENGTH

    if description && !description.strip.empty?
      errors.add(:description, "must be at least #{DESCRIPTION_MIN_LENGTH} characters") if description.strip.length < DESCRIPTION_MIN_LENGTH
      errors.add(:description, "must be #{DESCRIPTION_MAX_LENGTH} characters or less") if description.length > DESCRIPTION_MAX_LENGTH
    end

    current_year = Time.now.year
    unless established.is_a?(Integer) && established.between?(1900, current_year)
      errors.add(:established, "must be between 1900 and #{current_year}")
    end

    validates_format(EMAIL_REGEXP, :email, message: 'is not a valid email address') if email && !email.strip.empty?
    errors.add(:phone, 'must be a 10-digit phone number') if phone && !phone.strip.empty? && phone.gsub(/\D/, '').length != 10

    errors.add(:sqft_delivered, "must be #{SQFT_DELIVERED_MAX_LENGTH} characters or less") if sqft_delivered && sqft_delivered.length > SQFT_DELIVERED_MAX_LENGTH

    if website.present?
      errors.add(:website, "must be #{WEBSITE_MAX_LENGTH} characters or less") if website.length > WEBSITE_MAX_LENGTH
      errors.add(:website, 'must be a valid URL') unless website.match?(WEBSITE_REGEXP)
    end

    validate_status_change_guard
  end

  private

  # An Inactive Builder is excluded from Community creation (see
  # models/community.rb's own validate_builder) — so a Builder can't be
  # flipped to Inactive while it's still the active parent of real
  # Communities/Properties either, same "reassign first" guard as the
  # existing delete-guard (services/builders.rb#builder_stats' own
  # community_count/property_count, which this mirrors exactly).  Scoped to
  # `column_changed?(:status)` (never fires for `new?` — nothing can
  # reference a Builder that doesn't exist yet) so every other field on an
  # already-Inactive Builder keeps saving normally.
  def validate_status_change_guard
    return unless !new? && status == 'Inactive' && column_changed?(:status)

    has_communities = App::Models::Community.where(builder_id: id).count > 0
    has_properties = App::Models::Property.where(builder_id: id).exclude(publish_status: 'Archived').count > 0
    if has_communities || has_properties
      errors.add(:status, 'cannot be set to Inactive while Communities or Properties are still assigned to this Builder — reassign or archive them first')
    end
  end
end
