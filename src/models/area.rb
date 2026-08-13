class App::Models::Area < Sequel::Model
  one_to_many :locations

  # Unlike most other models here, AreaForm.js deliberately does NOT
  # duplicate these checks client-side — this validate is the single source
  # of truth for what's required/unique, and AreaForm.js just surfaces
  # whatever comes back from here. Keep it that way rather than re-adding
  # frontend-only requiredness checks.
  def validate
    super
    validates_presence [:name, :city, :state, :slug], message: 'is required'
    validates_unique :slug
    if name && (new? || column_changed?(:name))
      dup = self.class.where(Sequel.function(:lower, :name) => name.strip.downcase)
      dup = dup.exclude(id: id) unless new?
      errors.add(:name, 'already exists') if dup.first
    end
    validates_operator(:>=, 0, :avg_price_per_sqft) if avg_price_per_sqft
  end

  # city/state are mandatory (validated above) so they're never blank by the
  # time we get here; country and growth_pct are the two fields the product
  # spec calls out as "optional, defaults to X if left blank" — that default
  # belongs here (runs for both create and update) rather than in
  # AreaForm.js, so the frontend never has to invent a fallback value.
  def before_validation
    self.country = 'India' if country.to_s.strip.empty?
    self.growth_pct = 0 if growth_pct.nil?
    super
  end
end
