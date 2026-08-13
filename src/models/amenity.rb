class App::Models::Amenity < Sequel::Model
  # AmenitiesLibraryTab.js deliberately does NOT duplicate these checks
  # client-side (matching models/area.rb / models/builder.rb / models/
  # community.rb's approach) — this validate is the single source of truth,
  # and the tab just relays whatever comes back from here onto the matching
  # field.
  def validate
    super
    validates_presence [:name, :slug, :category], message: 'is required'
    validates_unique :slug

    if name && (new? || column_changed?(:name))
      dup = self.class.where(Sequel.function(:lower, :name) => name.strip.downcase)
      dup = dup.exclude(id: id) unless new?
      errors.add(:name, 'already exists') if dup.first
    end
  end
end
