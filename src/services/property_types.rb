class App::Services::PropertyTypes < App::Services::Base
  def model; PropertyType; end

  # Mirrors lib/data/propertyTypes.js: the taxonomy is small and always shown
  # in its curated displayOrder, so list (unlike Builders' created_at-desc)
  # orders by display_order asc. Same search-by-name / archived-scope
  # convention as Builders#list otherwise.
  SORTABLE_COLUMNS = %w[name display_order created_at].freeze

  def list
    ds = model
    ds = ds.where(archived: qs[:archived].to_s == 'true') if qs.key?(:archived)
    if qs[:search].present?
      ds = ds.where(Sequel.like(:name, "%#{qs[:search]}%", case_insensitive: true))
    end
    ds = apply_sort(ds, SORTABLE_COLUMNS, default: [[:display_order, :asc], [:id, :asc]])

    # Grouped over the whole `properties` table in one query regardless of
    # which page of PropertyTypes is being returned, so this stays correct
    # (and no more expensive) under pagination.
    counts, avg_prices = property_stats_by_type
    paginated_response(ds) { |t|
      t.to_pos.merge(
        'listings_count' => counts[t.id] || 0,
        'avg_price' => avg_prices[t.id] ? avg_prices[t.id].to_i : 0
      )
    }
  end

  # lib/data/propertyTypes.js's addPropertyType defaults displayOrder to
  # "end of the list" (propertyTypes.length + 1) when the caller doesn't pick
  # one; replicate that here rather than pushing the default onto the frontend.
  def create
    data = data_for(:save)
    data[:display_order] = data[:display_order].presence || (model.max(:display_order).to_i + 1)
    save(model.new(data))
  end

  # Archive/restore (archivePropertyType/restorePropertyType in the mock) and
  # reordering (reorderPropertyTypes) are all plain-field updates from the
  # frontend's point of view, so they ride the standard PUT/update below —
  # `archived` and `display_order` are just whitelisted like any other
  # saveable field, same pattern as Builders.
  # `icon`/`colour` are intentionally no longer whitelisted — the taxonomy
  # was simplified to drop styling in favor of Name/Description/Display
  # Order/Allow Search/Homepage Visibility/SEO only (the admin form no
  # longer sends either field). Columns are left in place for now rather
  # than dropped in the same change — see the trailing migration once
  # confirmed nothing else still reads them.
  #
  # `active` is likewise no longer whitelisted — the taxonomy's lifecycle
  # was simplified from Active/Inactive/Archived down to just Active/
  # Archived (the `archived` column above is the sole source of truth now).
  # The column itself is left in place, unused, same as `icon`/`colour`.
  def self.fields
    {
      save: [
        :slug, :name, :description, :banner, :image, :display_order,
        :show_on_homepage, :allow_search, :seo, :archived
      ]
    }
  end

  private

  # Replaces the frontend's old lib/data/propertyTypes.js `propertyTypeStats`
  # mock (stale, hand-authored numbers) with real aggregates over the live
  # `properties` table — Archived listings are excluded via `publish_status`
  # (the single source of truth, see models/property.rb), matching the
  # admin dashboard's own `activeProperties` convention (AdminClient.js).
  def property_stats_by_type
    active = Property.exclude(publish_status: 'Archived')
    counts = active.group_and_count(:property_type_id).as_hash(:property_type_id, :count)
    avg_prices = active.exclude(price: nil).group(:property_type_id).select_hash(:property_type_id, Sequel.function(:avg, :price).as(:avg_price))
    [counts, avg_prices]
  end
end
