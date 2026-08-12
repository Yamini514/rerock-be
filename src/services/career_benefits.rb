class App::Services::CareerBenefits < App::Services::Base
  def model; CareerBenefit; end

  # Mirrors lib/data/careers.js's benefits[]: no fixed sort order in the
  # mock, so newest-first same as JobOpenings. Search across title/
  # description only — no category/type concept for this resource.
  SORTABLE_COLUMNS = %w[title created_at].freeze

  def list
    ds = model
    if qs[:search].present?
      term = "%#{qs[:search]}%"
      ds = ds.where(Sequel.like(:title, term, case_insensitive: true) | Sequel.like(:description, term, case_insensitive: true))
    end
    ds = apply_sort(ds, SORTABLE_COLUMNS, default: [[:created_at, :desc], [:id, :desc]])
    paginated_response(ds)
  end

  # No archive/restore/status-transition concept (same as the mock's plain
  # addBenefit/updateBenefit/deleteBenefit) — every field is a standard
  # PUT/update.
  def self.fields
    {
      save: [
        :title, :description
      ]
    }
  end
end
