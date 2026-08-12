class App::Services::Properties < App::Services::Base
  def model; Property; end

  # Mirrors lib/data/properties.js's own filter shape: search by title, plus
  # exact filters for community/builder/property type/status, and the
  # Active/Archived scope shared by every Property Catalog resource so far.
  #
  # community_id/builder_id/property_type_id/area_id/status/bedrooms all
  # accept a comma-separated list (Explore Properties' multi-select filters)
  # in addition to a single value — splitting a single value is a no-op
  # (`"3".split(',') == ["3"]`), so every existing single-value caller
  # (admin list, property detail lookups) is unaffected.
  SORTABLE_COLUMNS = %w[title price created_at status].freeze

  def list
    ds = model
    ds = ds.where(archived: qs[:archived].to_s == 'true') if qs.key?(:archived)
    ds = ds.where(community_id: ids_from(qs[:community_id])) if qs[:community_id].present?
    ds = ds.where(builder_id: ids_from(qs[:builder_id])) if qs[:builder_id].present?
    ds = ds.where(property_type_id: ids_from(qs[:property_type_id])) if qs[:property_type_id].present?
    ds = ds.where(area_id: ids_from(qs[:area_id])) if qs[:area_id].present?
    ds = ds.where(status: qs[:status].to_s.split(',')) if qs[:status].present?
    # Exact-slug lookup — added for the public/RAM-Portal browse endpoint
    # (routes.rb's 'public' block), whose property detail pages route by
    # slug rather than the real numeric id. Harmless additive filter for
    # every other existing caller (admin list page never passes `slug`).
    ds = ds.where(slug: qs[:slug]) if qs[:slug].present?
    if qs[:search].present?
      ds = ds.where(Sequel.like(:title, "%#{qs[:search]}%", case_insensitive: true))
    end
    ds = ds.where(bedrooms_filter(qs[:bedrooms])) if qs[:bedrooms].present?
    if qs[:min_price].present? && qs[:max_price].present?
      ds = ds.where(price: qs[:min_price].to_i..qs[:max_price].to_i)
    end
    ds = ds.where(rera: true) if qs[:rera].to_s == 'true'
    if qs[:min_investment_score].present? && qs[:min_investment_score].to_i > 0
      score = qs[:min_investment_score].to_i
      ds = ds.where(community_id: Community.where(Sequel.expr(:investment_score) >= score).select(:id))
    end
    ds = ds.where(amenity_filter(ids_from(qs[:amenity_ids]))) if qs[:amenity_ids].present?
    ds = apply_sort(ds, SORTABLE_COLUMNS, default: [[:created_at, :desc]])

    # Opt-in: a caller that doesn't send `page` gets the exact bare-array
    # response it always has (every existing admin/public caller) — fully
    # non-breaking. `offset`/`limit`/`page_size` already exist on Base
    # (previously unused here) — this table is the one most likely to
    # outgrow an unpaginated `.all` as the catalog grows.
    paginated_response(ds)
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
        :slug, :title, :community_id, :builder_id, :area_id, :location_id, :property_type_id,
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

  private

  def ids_from(raw)
    raw.to_s.split(',').map(&:strip).reject(&:empty?).map(&:to_i)
  end

  # Bedroom pills are exact digits plus a "5+" catch-all — combine an exact
  # IN-list with a `>= 5` clause rather than trying to express "5+" as a
  # single value the DB understands.
  def bedrooms_filter(raw)
    values = raw.to_s.split(',').map(&:strip)
    has_plus = values.delete('5+')
    exact = values.reject(&:empty?).map(&:to_i)

    cond = exact.present? ? Sequel.expr({ bedrooms: exact }) : nil
    plus_cond = has_plus ? Sequel.virtual_row { bedrooms >= 5 } : nil
    [cond, plus_cond].compact.reduce(:|)
  end

  # Mirrors the frontend's old client-side rule (PropertiesClient.js): a
  # property matches on its own amenity_ids when it has any set, otherwise
  # falls back to its community's amenity_ids. Expressed as a subquery
  # against Community rather than a join, so the outer property dataset's
  # column set/`.all.map(&:to_pos)` shape is untouched.
  def amenity_filter(ids)
    pg_ids = Sequel.pg_array(ids, :integer)
    matching_community_ids = Community.where(Sequel.pg_array_op(:amenity_ids).overlaps(pg_ids)).select(:id)
    Sequel.|(
      Sequel.pg_array_op(:amenity_ids).overlaps(pg_ids),
      Sequel.&(Sequel.lit('cardinality(amenity_ids) = 0'), { community_id: matching_community_ids })
    )
  end
end
