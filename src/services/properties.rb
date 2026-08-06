class App::Services::Properties < App::Services::Base
  def model; Property; end

  # Mirrors lib/data/properties.js's own filter shape: search by title, plus
  # exact filters for community/builder/property type/status, and the
  # Active/Archived scope shared by every Property Catalog resource so far.
  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(archived: qs[:archived].to_s == 'true') if qs.key?(:archived)
    ds = ds.where(community_id: qs[:community_id]) if qs[:community_id].present?
    ds = ds.where(builder_id: qs[:builder_id]) if qs[:builder_id].present?
    ds = ds.where(property_type_id: qs[:property_type_id]) if qs[:property_type_id].present?
    ds = ds.where(area_id: qs[:area_id]) if qs[:area_id].present?
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    # Exact-slug lookup — added for the public/RAM-Portal browse endpoint
    # (routes.rb's 'public' block), whose property detail pages route by
    # slug rather than the real numeric id. Harmless additive filter for
    # every other existing caller (admin list page never passes `slug`).
    ds = ds.where(slug: qs[:slug]) if qs[:slug].present?
    if qs[:search].present?
      ds = ds.where(Sequel.like(:title, "%#{qs[:search]}%", case_insensitive: true))
    end
    return_success(ds.all.map(&:to_pos))
  end

  # Archive/restore (archiveProperty/restoreProperty), the featured toggle
  # (toggleFeatured), and quick status changes are all plain flips of a
  # column, so they ride the standard PUT/update below — whitelisted like
  # any other saveable field, same pattern as every other Property Catalog
  # resource. `tag_ids`/`amenity_ids` are plain Postgres integer[] columns
  # (same precedent as Community's `amenity_ids` in migrations/0011 /
  # services/communities.rb) — no join-table code needed here either.
  def self.fields
    {
      save: [
        :slug, :title, :community_id, :builder_id, :area_id, :location_id, :locality, :property_type_id,
        :status, :price, :price_per_sqft, :built_up_area, :land_area, :created_date,
        :bedrooms, :bathrooms, :balconies, :facing, :floor, :rera,
        :images, :highlights, :description, :floor_plans, :pricing_trend,
        :agent_slug, :featured, :tag_ids, :amenity_ids, :investment_score, :advisor_notes,
        :sales_team, :publish_status, :publish_at, :seo, :videos, :tour_360, :virtual_tour,
        :documents, :archived,
        :code, :configuration, :unit_number, :offer_price, :booking_amount, :maintenance,
        :pricing_notes, :parking, :furnishing, :advantages, :specifications
      ]
    }
  end
end
