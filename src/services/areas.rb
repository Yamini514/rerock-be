class App::Services::Areas < App::Services::Base
  def model; Area; end

  # Mirrors lib/data/areas.js: areas are shown in their curated displayOrder
  # (same convention as PropertyTypes#list), plus name search and the
  # Active/Archived scope shared by every Property Catalog resource so far.
  def list
    ds = model.order(:display_order, :id)
    ds = ds.where(archived: qs[:archived].to_s == 'true') if qs.key?(:archived)
    if qs[:search].present?
      ds = ds.where(Sequel.like(:name, "%#{qs[:search]}%", case_insensitive: true))
    end
    return_success(ds.all.map(&:to_pos))
  end

  # lib/data/areas.js's addArea defaults displayOrder to "end of the list"
  # (areas.length + 1) when the caller doesn't pick one; replicate that here,
  # same pattern as PropertyTypes#create.
  def create
    data = data_for(:save)
    data[:display_order] = data[:display_order].presence || (model.max(:display_order).to_i + 1)
    save(model.new(data))
  end

  # Archive/restore (archiveArea/restoreArea in the mock) are plain flips of
  # the `archived` column, so they ride the standard PUT/update below —
  # `archived` is whitelisted like any other saveable field, same pattern as
  # Builders/PropertyTypes.
  def self.fields
    {
      save: [
        :slug, :name, :city, :state, :country, :image, :avg_price_per_sqft, :growth_pct,
        :lat, :lng, :description, :display_order, :active, :seo, :archived
      ]
    }
  end
end
