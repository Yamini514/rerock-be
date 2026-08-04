class App::Services::SeoPages < App::Services::Base
  def model; SeoPage; end

  # Mirrors lib/data/seoPages.js: no fixed sort order in the mock (it's just
  # the literal array), so newest-first same as FAQs/Blogs/Testimonials.
  # Search covers both `route` and `meta_title` (per the task's "search by
  # route/title") since an admin hunting for a page's SEO row is equally
  # likely to remember the path or the title, not just one of the two.
  def list
    ds = model.order(Sequel.desc(:created_at), Sequel.desc(:id))
    if qs[:search].present?
      term = "%#{qs[:search]}%"
      ds = ds.where(Sequel.like(:route, term, case_insensitive: true) | Sequel.like(:meta_title, term, case_insensitive: true))
    end
    return_success(ds.all.map(&:to_pos))
  end

  # No archive/restore/status-transition concept (same as the mock's plain
  # updateSeoPage) — every field is a standard PUT/update. `route` is
  # included in :save (not just :create-only) since the mock never actually
  # renames a route in place, but there's no reason to forbid it here.
  def self.fields
    {
      save: [
        :route, :meta_title, :meta_description, :score
      ]
    }
  end
end
