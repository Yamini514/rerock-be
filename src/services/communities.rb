class App::Services::Communities < App::Services::Base
  def model; Community; end

  # Mirrors lib/data/communities.js: search by name, plus filters for the
  # three FKs (builder/area/location) and status, and the Active/Archived
  # scope shared by every Property Catalog resource so far.
  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(archived: qs[:archived].to_s == 'true') if qs.key?(:archived)
    ds = ds.where(builder_id: qs[:builder_id]) if qs[:builder_id].present?
    ds = ds.where(area_id: qs[:area_id]) if qs[:area_id].present?
    ds = ds.where(location_id: qs[:location_id]) if qs[:location_id].present?
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    if qs[:search].present?
      ds = ds.where(Sequel.like(:name, "%#{qs[:search]}%", case_insensitive: true))
    end
    return_success(ds.all.map(&:to_pos))
  end

  # Archive/restore (archiveCommunity/restoreCommunity in the mock) and the
  # featured toggle (toggleCommunityFeatured) are all plain flips of a column,
  # so they ride the standard PUT/update below — whitelisted like any other
  # saveable field, same pattern as every other Property Catalog resource.
  #
  # amenity_ids is a plain Postgres integer[] (see migrations/0011 and
  # ARCHITECTURE.md for why this was chosen over a community_amenities join
  # table): Base#create/#update just slice params via data_for(:save) and
  # assign them straight onto the model, so an array field flows through
  # exactly like Builder's awards/certifications text[] columns already do —
  # no custom many-to-many code needed here at all.
  def self.fields
    {
      save: [
        :slug, :name, :type, :builder_id, :area_id, :location_id, :tagline, :status,
        :featured, :trending, :homepage_visibility, :rera, :price_min, :price_max,
        :unit_types, :total_units, :available_units, :possession, :investment_score,
        :growth_pct, :last_price_update, :hero_image, :gallery, :overview, :master_plan,
        :amenity_ids, :pricing_trend, :nearby, :documents, :seo, :archived
      ]
    }
  end
end
