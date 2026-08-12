class App::Services::Testimonials < App::Services::Base
  def model; Testimonial; end

  # Mirrors lib/data/testimonials.js: newest-first, search by name, plus an
  # exact status filter for the admin page's Approved/Pending/Rejected
  # workflow (the list page's approve/reject actions filter/act on Pending
  # rows client-side today, but the filter is exposed here too so a future
  # status-scoped view doesn't need a new endpoint).
  SORTABLE_COLUMNS = %w[name rating status created_at].freeze

  def list
    ds = model
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    if qs[:search].present?
      ds = ds.where(Sequel.like(:name, "%#{qs[:search]}%", case_insensitive: true))
    end
    ds = apply_sort(ds, SORTABLE_COLUMNS, default: [[:created_at, :desc], [:id, :desc]])
    paginated_response(ds)
  end

  # No archive/restore concept (same as Blogs/Leads) — approve/reject are
  # just a `status` transition and ride the standard PUT/update below,
  # `status` whitelisted like any other saveable field.
  def self.fields
    {
      save: [
        :name, :role, :rating, :quote, :status, :show_on_homepage
      ]
    }
  end
end
