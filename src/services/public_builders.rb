# Public, read-only builder directory — subclasses the real Builders
# service (services/builders.rb) purely to reuse its #to_pos +
# builder_stats merge (rating/review_count/community_count/property_count)
# unchanged, just scoped to real, live builders only. Builders#list/#get
# (the admin CRUD version, still mounted separately for staff) intentionally
# shows every Active/Archived builder so admins can manage Archived ones —
# this public mount must never leak those.
class App::Services::PublicBuilders < App::Services::Builders
  def list
    ds = model.where(archived: false)
    if qs[:search].present?
      ds = ds.where(Sequel.like(:name, "%#{qs[:search]}%", case_insensitive: true))
    end
    ds = apply_sort(ds, SORTABLE_COLUMNS, default: [[:created_at, :desc]])
    stats = builder_stats
    paginated_response(ds) { |b| b.to_pos.merge(stats[b.id] || default_stats) }
  end

  def get
    return_errors!('Builder not found.', 404) if item.archived
    stats = builder_stats(item.id)
    return_success(item.to_pos.merge(stats[item.id] || default_stats))
  end
end
