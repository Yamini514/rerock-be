class App::Models::Community < Sequel::Model
  many_to_one :builder
  many_to_one :area
  many_to_one :location

  # Defense-in-depth under CommunityForm.js's own client-side checks.
  # `location_id` is deliberately excluded from presence (migrations/0053
  # made it nullable on purpose, replaced by free-text `locality`); `slug`
  # uniqueness mirrors the already-existing DB unique index
  # (migrations/0011). The price_min/price_max ordering check only fires
  # when those columns are actually being touched (`column_changed?`, via
  # the globally-loaded `:dirty` plugin) or on a brand-new row — so an
  # unrelated edit to an old row that already has bad legacy price data
  # (from before this check existed) doesn't suddenly start failing.
  def validate
    super
    validates_presence [:name, :slug, :builder_id, :area_id]
    validates_unique :slug
    validates_operator(:>=, 0, :price_min) if price_min
    validates_operator(:>=, 0, :price_max) if price_max
    if price_min && price_max && price_max < price_min && (new? || column_changed?(:price_min) || column_changed?(:price_max))
      errors.add(:price_max, 'must be greater than or equal to price_min')
    end
  end
end
