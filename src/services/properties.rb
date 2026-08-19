class App::Services::Properties < App::Services::Base
  def model; Property; end

  # Mirrors lib/data/properties.js's own filter shape: search by title, plus
  # exact filters for community/builder/property type/status/publish_status.
  #
  # community_id/builder_id/property_type_id/area_id/status/publish_status/
  # bedrooms all accept a comma-separated list (Explore Properties' multi-
  # select filters) in addition to a single value — splitting a single value
  # is a no-op (`"3".split(',') == ["3"]`), so every existing single-value
  # caller (admin list, property detail lookups) is unaffected.
  SORTABLE_COLUMNS = %w[title price created_at status publish_status].freeze

  def list
    ds = apply_sort(filtered_dataset, SORTABLE_COLUMNS, default: [[:created_at, :desc]])

    # Opt-in: a caller that doesn't send `page` gets the exact bare-array
    # response it always has (every existing admin/public caller) — fully
    # non-breaking. `offset`/`limit`/`page_size` already exist on Base
    # (previously unused here) — this table is the one most likely to
    # outgrow an unpaginated `.all` as the catalog grows.
    paginated_response(ds)
  end

  # `builder_id`/`area_id` are derived from the chosen Community (never
  # trusted from the client) so a Property can't silently drift from its
  # Community's real builder/area — Builder/Area are read-only, derived
  # fields in PropertyForm.js precisely because this is enforced here.
  # `price_per_sqft` is likewise always recomputed from `price`/
  # `built_up_area` rather than accepted from the client.
  def create
    data = data_for(:save)
    apply_community_derivations!(data)
    compute_price_per_sqft!(data)
    save(model.new(data))
  end

  # The featured toggle (toggleFeatured) and quick status changes are plain
  # flips of a column, so they ride this update below — whitelisted like any
  # other saveable field, same pattern as every other Property Catalog
  # resource. Archive/restore is likewise a plain flip, but of
  # `publish_status` (to/from 'Archived') now — `archived` is no longer
  # whitelisted below, see models/property.rb's own publish_status/
  # publish_at validation for the single source of truth this replaced it
  # with. `tag_ids`/`amenity_ids` are plain Postgres integer[] columns (same
  # precedent as Community's `amenity_ids` in migrations/0011 /
  # services/communities.rb) — no join-table code needed here either.
  def update(data = nil)
    data ||= data_for(:save)
    apply_community_derivations!(data)
    compute_price_per_sqft!(data)
    item.set_fields(data, data.keys)
    save(item)
  end

  def self.fields
    {
      save: [
        :slug, :title, :community_id, :builder_id, :area_id, :location_id, :property_type_id,
        :status, :price, :price_per_sqft, :built_up_area, :land_area,
        :bedrooms, :bathrooms, :balconies, :facing, :floor,
        :images, :highlights, :description, :floor_plans,
        :agent_slug, :agent_id, :featured, :tag_ids, :amenity_ids, :advisor_notes,
        :sales_team, :publish_status, :publish_at, :seo, :videos, :tour_360, :virtual_tour,
        :documents,
        :code, :configuration, :unit_number, :offer_price, :booking_amount, :maintenance,
        :pricing_notes, :parking, :furnishing, :advantages, :specifications
      ]
    }
  end

  protected

  # Every filter `list` applies before sorting/pagination, pulled out so
  # PublicProperties#list (services/public_properties.rb) can reuse the
  # exact same community/builder/search/bedrooms/price/rera/amenity filters
  # and just AND its own public-visibility scope onto the result, rather
  # than re-implementing any of this.
  def filtered_dataset
    # Eager-loaded so Property#to_pos's community&.rera_status merge doesn't
    # fire one extra query per row on top of this dataset's own.
    ds = model.eager(:community)
    # Replaces the old plain `archived` boolean filter — the admin list's
    # Active/Archived view toggle (and every other publish-state filter) now
    # reads/writes `publish_status` exclusively, same single-source-of-truth
    # change as models/property.rb's own validation.
    ds = ds.where(publish_status: qs[:publish_status].to_s.split(',')) if qs[:publish_status].present?
    ds = ds.where(community_id: ids_from(qs[:community_id])) if qs[:community_id].present?
    ds = ds.where(builder_id: ids_from(qs[:builder_id])) if qs[:builder_id].present?
    ds = ds.where(property_type_id: ids_from(qs[:property_type_id])) if qs[:property_type_id].present?
    ds = ds.where(area_id: ids_from(qs[:area_id])) if qs[:area_id].present?
    ds = ds.where(agent_id: ids_from(qs[:agent_id])) if qs[:agent_id].present?
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
    # RERA lives on Community now (rera_status/rera — see
    # models/community.rb), not on Property, so "RERA Approved" is
    # expressed as a subquery the same way min_investment_score already is.
    if qs[:rera].to_s == 'true'
      ds = ds.where(community_id: Community.where(rera_status: 'Approved').select(:id))
    end
    if qs[:min_investment_score].present? && qs[:min_investment_score].to_i > 0
      score = qs[:min_investment_score].to_i
      ds = ds.where(community_id: Community.where(Sequel.expr(:investment_score) >= score).select(:id))
    end
    ds = ds.where(amenity_filter(ids_from(qs[:amenity_ids]))) if qs[:amenity_ids].present?
    ds
  end

  private

  # Only touches builder_id/area_id when the payload actually sets/changes
  # community_id (PropertyForm.js always sends it; a narrower partial
  # update like the list page's quick-status-change or "Mark Featured"
  # bulk action won't include it, and must leave builder_id/area_id alone).
  def apply_community_derivations!(data)
    return unless data.key?(:community_id) && data[:community_id].present?
    community = Community[data[:community_id].to_i]
    return unless community
    data[:builder_id] = community.builder_id
    data[:area_id] = community.area_id
  end

  # Only recomputes when the payload actually carries both price and
  # built_up_area (again, PropertyForm.js always sends both; a narrower
  # partial update that doesn't touch either one leaves the existing
  # price_per_sqft alone rather than nulling it out).
  def compute_price_per_sqft!(data)
    return unless data.key?(:price) && data.key?(:built_up_area)
    price = data[:price]
    area = data[:built_up_area]
    data[:price_per_sqft] = (price && area && area.to_f > 0) ? (price.to_f / area.to_f).round : nil
  end

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

  # A property matches on its own (property-specific extra) amenity_ids,
  # OR its community's amenity_ids — additive/inherited, not an
  # override-if-present. Expressed as a subquery against Community rather
  # than a join, so the outer property dataset's column set/
  # `.all.map(&:to_pos)` shape is untouched.
  def amenity_filter(ids)
    pg_ids = Sequel.pg_array(ids, :integer)
    matching_community_ids = Community.where(Sequel.pg_array_op(:amenity_ids).overlaps(pg_ids)).select(:id)
    Sequel.|(
      Sequel.pg_array_op(:amenity_ids).overlaps(pg_ids),
      { community_id: matching_community_ids }
    )
  end
end
