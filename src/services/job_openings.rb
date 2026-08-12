class App::Services::JobOpenings < App::Services::Base
  def model; JobOpening; end

  # Mirrors lib/data/careers.js's openRoles[]: no fixed sort order in the
  # mock (it's just the literal array), so newest-first same as Faqs/
  # Testimonials/Blogs. Search across title/department/location (the
  # Table's searchPlaceholder covers all three visually), plus an exact
  # `type` filter for the JOB_TYPES enum.
  SORTABLE_COLUMNS = %w[title department location type created_at].freeze

  def list
    ds = model
    ds = ds.where(type: qs[:type]) if qs[:type].present?
    if qs[:search].present?
      term = "%#{qs[:search]}%"
      ds = ds.where(
        Sequel.like(:title, term, case_insensitive: true) |
        Sequel.like(:department, term, case_insensitive: true) |
        Sequel.like(:location, term, case_insensitive: true)
      )
    end
    ds = apply_sort(ds, SORTABLE_COLUMNS, default: [[:created_at, :desc], [:id, :desc]])
    paginated_response(ds)
  end

  # No archive/restore/status-transition concept (same as the mock's plain
  # addJobRole/updateJobRole/deleteJobRole) — every field is a standard
  # PUT/update.
  def self.fields
    {
      save: [
        :title, :department, :location, :type
      ]
    }
  end
end
