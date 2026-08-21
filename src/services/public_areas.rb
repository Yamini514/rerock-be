# Public, read-only area directory — subclasses the real Areas service
# (services/areas.rb) purely to reuse its #to_pos + stats_by_area merge
# (property_count/community_count/builder_count) unchanged, just scoped to
# real, live areas only. Same "subclass the admin service, narrow the scope"
# convention as services/public_builders.rb. Areas#list/#get (the admin CRUD
# version, still mounted separately for staff) intentionally shows every
# Active/Archived area so admins can manage Archived ones; this public mount
# must never leak those into the site's location dropdowns/filters.
class App::Services::PublicAreas < App::Services::Areas
  def list
    ds = model.where(archived: false)
    if qs[:search].present?
      ds = ds.where(Sequel.like(:name, "%#{qs[:search]}%", case_insensitive: true))
    end
    ds = apply_sort(ds, SORTABLE_COLUMNS, default: [[:display_order, :asc], [:id, :asc]])

    property_counts, community_counts, builder_counts, live_property_counts = stats_by_area
    paginated_response(ds) { |a|
      a.to_pos.merge(
        'property_count' => property_counts[a.id] || 0,
        'community_count' => community_counts[a.id] || 0,
        'builder_count' => builder_counts[a.id] || 0,
        'live_property_count' => live_property_counts[a.id] || 0
      )
    }
  end

  def get
    return_errors!('Area not found.', 404) if item.archived

    property_counts, community_counts, builder_counts, live_property_counts = stats_by_area
    return_success(
      item.to_pos.merge(
        'property_count' => property_counts[item.id] || 0,
        'community_count' => community_counts[item.id] || 0,
        'builder_count' => builder_counts[item.id] || 0,
        'live_property_count' => live_property_counts[item.id] || 0
      )
    )
  end
end
