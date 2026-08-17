# Public, read-only builder directory — subclasses the real Builders
# service (services/builders.rb) purely to reuse its #to_pos +
# builder_stats merge (rating/review_count/community_count/property_count)
# unchanged, just scoped to real, live builders only. Builders#list/#get
# (the admin CRUD version, still mounted separately for staff) intentionally
# shows every status/archived state so admins can manage Inactive/Archived
# builders — this public mount must never leak those, especially now that a
# brand-new builder briefly exists as `status: 'Inactive'` mid-way through
# the Add Builder wizard (see BuilderForm.js's own `persist` — the
# "Save & Next" progressive save creates the real row on the very first tab,
# well before the admin reaches the actual "Create Builder" submit).
class App::Services::PublicBuilders < App::Services::Builders
  def list
    ds = model.where(status: 'Active', archived: false)
    if qs[:search].present?
      ds = ds.where(Sequel.like(:name, "%#{qs[:search]}%", case_insensitive: true))
    end
    ds = apply_sort(ds, SORTABLE_COLUMNS, default: [[:created_at, :desc]])
    stats = builder_stats
    paginated_response(ds) { |b| b.to_pos.merge(stats[b.id] || default_stats) }
  end

  def get
    return_errors!('Builder not found.', 404) unless item.status == 'Active' && !item.archived
    stats = builder_stats(item.id)
    return_success(item.to_pos.merge(stats[item.id] || default_stats))
  end
end
