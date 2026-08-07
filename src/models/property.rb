class App::Models::Property < Sequel::Model
  many_to_one :community
  many_to_one :builder
  many_to_one :area
  many_to_one :location
  many_to_one :property_type

  # Defense-in-depth under PropertyForm.js's own client-side checks — a
  # direct API call bypasses those entirely today. `location_id` is
  # deliberately excluded from presence (migrations/0053 made it nullable
  # on purpose); `slug` uniqueness mirrors the already-existing DB unique
  # index (migrations/0012), so this only surfaces a nicer error earlier,
  # it doesn't change what's allowed.
  def validate
    super
    validates_presence [:title, :slug, :community_id, :builder_id, :area_id, :property_type_id]
    validates_unique :slug
    validates_operator(:>=, 0, :price) if price
    validates_operator(:>=, 0, :built_up_area) if built_up_area
    validates_operator(:>=, 0, :land_area) if land_area
  end
end
