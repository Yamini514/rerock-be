class App::Services::Faqs < App::Services::Base
  def model; Faq; end

  # Mirrors lib/data/faqs.js: no fixed sort order in the mock (it's just the
  # literal array), so newest-first same as Testimonials/Blogs. Exact
  # `category` filter (the admin page's Category `Select`, driven by the
  # distinct values derived from the fetched list itself — see the migration
  # comment) plus a search across both question and answer text, since a
  # freeform FAQ search naturally means "does this appear anywhere in Q or A."
  SORTABLE_COLUMNS = %w[category q created_at].freeze

  def list
    ds = model
    ds = ds.where(category: qs[:category]) if qs[:category].present?
    if qs[:search].present?
      term = "%#{qs[:search]}%"
      ds = ds.where(Sequel.like(:q, term, case_insensitive: true) | Sequel.like(:a, term, case_insensitive: true))
    end
    ds = apply_sort(ds, SORTABLE_COLUMNS, default: [[:created_at, :desc], [:id, :desc]])
    paginated_response(ds)
  end

  # No archive/restore/status-transition concept (same as the mock's plain
  # addFaq/updateFaq/deleteFaq) — every field is a standard PUT/update.
  def self.fields
    {
      save: [
        :category, :q, :a
      ]
    }
  end
end
