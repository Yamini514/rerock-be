class App::Services::Amenities < App::Services::Base
  def model; Amenity; end

  # Mirrors lib/data/amenities.js: no curated displayOrder or archived scope
  # for this resource (the admin tab has neither an archive flow nor manual
  # reordering — just an Active/Inactive status column), so this is ordered
  # alphabetically instead. Supports name search and an exact category filter
  # (categories are the fixed AMENITY_CATEGORIES list on the frontend), same
  # search-and-filter convention as every other Property Catalog resource.
  def list
    ds = model.order(:name)
    ds = ds.where(category: qs[:category]) if qs[:category].present?
    if qs[:search].present?
      ds = ds.where(Sequel.like(:name, "%#{qs[:search]}%", case_insensitive: true))
    end
    return_success(ds.all.map(&:to_pos))
  end

  def self.fields
    {
      save: [:slug, :name, :icon, :category, :active]
    }
  end
end
