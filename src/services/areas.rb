class App::Services::Areas < App::Services::Base
  def model; Area; end

  # Mirrors lib/data/areas.js: areas are shown in their curated displayOrder
  # (same convention as PropertyTypes#list), plus name search and the
  # Active/Archived scope shared by every Property Catalog resource so far.
  SORTABLE_COLUMNS = %w[name display_order created_at].freeze

  def list
    ds = model
    ds = ds.where(archived: qs[:archived].to_s == 'true') if qs.key?(:archived)
    if qs[:search].present?
      ds = ds.where(Sequel.like(:name, "%#{qs[:search]}%", case_insensitive: true))
    end
    ds = apply_sort(ds, SORTABLE_COLUMNS, default: [[:display_order, :asc], [:id, :asc]])

    # Grouped over the whole Properties/Communities tables in one query
    # regardless of which page of Areas is being returned — unaffected by
    # pagination, same as PropertyTypes#property_stats_by_type.
    property_counts, community_counts, builder_counts = stats_by_area
    paginated_response(ds) { |a|
      a.to_pos.merge(
        'property_count' => property_counts[a.id] || 0,
        'community_count' => community_counts[a.id] || 0,
        'builder_count' => builder_counts[a.id] || 0
      )
    }
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

  private

  # Replaces the frontend's old lib/data/areas.js `areaStats` mock (computed
  # over fixture properties/communities) with real aggregates over the live
  # `properties`/`communities` tables — Properties are excluded via
  # `publish_status != 'Archived'` (the single source of truth, see
  # models/property.rb), same convention as PropertyTypes#
  # property_stats_by_type; Communities keep their own separate `archived`
  # column untouched. builder_count is deliberately derived from this area's
  # Properties (not Communities), matching the mock's own areaStats()
  # exactly.
  def stats_by_area
    active_properties = Property.exclude(publish_status: 'Archived')
    active_communities = Community.where(archived: false)

    property_counts = active_properties.group_and_count(:area_id).as_hash(:area_id, :count)
    community_counts = active_communities.group_and_count(:area_id).as_hash(:area_id, :count)
    # Distinct (area_id, builder_id) pairs, wrapped in a subquery (`from_self`)
    # so the outer GROUP BY counts distinct builders per area rather than
    # every property row.
    builder_counts = active_properties.select(:area_id, :builder_id).distinct.from_self
      .group_and_count(:area_id).as_hash(:area_id, :count)

    [property_counts, community_counts, builder_counts]
  end
end
