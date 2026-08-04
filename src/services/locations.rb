class App::Services::Locations < App::Services::Base
  def model; Location; end

  # Mirrors lib/data/locations.js: localities are shown in their curated
  # displayOrder, plus name search and the Active/Archived scope shared by
  # every Property Catalog resource so far. `area_id` is accepted as an extra
  # filter (not used by the current admin page, which fetches the full list
  # and builds its own tree, but useful for any future scoped lookup).
  def list
    ds = model.order(:display_order, :id)
    ds = ds.where(archived: qs[:archived].to_s == 'true') if qs.key?(:archived)
    ds = ds.where(area_id: qs[:area_id]) if qs[:area_id].present?
    if qs[:search].present?
      ds = ds.where(Sequel.like(:name, "%#{qs[:search]}%", case_insensitive: true))
    end
    return_success(ds.all.map(&:to_pos))
  end

  # lib/data/locations.js's addLocation defaults displayOrder to "end of the
  # list" (locations.length + 1), same pattern as Areas/PropertyTypes#create.
  # It also leaves `city` unset unless explicitly passed; since we now have a
  # real `area_id` FK, default city from the parent Area's own city instead of
  # requiring the admin to retype it on every locality.
  def create
    data = data_for(:save)
    data[:display_order] = data[:display_order].presence || (model.max(:display_order).to_i + 1)
    if data[:city].blank? && data[:area_id].present?
      area = Area[data[:area_id]]
      data[:city] = area.city if area
    end
    save(model.new(data))
  end

  # Archive/restore (archiveLocation/restoreLocation in the mock) are plain
  # flips of the `archived` column, so they ride the standard PUT/update
  # below — whitelisted like any other saveable field, same pattern as
  # every other Property Catalog resource so far.
  def self.fields
    {
      save: [
        :slug, :name, :area_id, :city, :pincode, :lat, :lng, :metro, :bus,
        :nearby_landmarks, :schools, :hospitals, :airport_distance_km,
        :display_order, :status, :seo, :archived
      ]
    }
  end
end
