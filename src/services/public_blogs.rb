# Unauthenticated, read-only — only "Published" posts (never "Draft"),
# regardless of any query param. Same forced-status-server-side pattern as
# PublicReviews/PublicTestimonials. Exact-slug filter for detail pages
# mirrors Properties#list's own `slug` param (services/properties.rb) rather
# than a separate get-by-slug route.
class App::Services::PublicBlogs < App::Services::Base
  def model; Blog; end

  def list
    ds = model.where(status: 'Published').order(Sequel.desc(:date), Sequel.desc(:id))
    ds = ds.where(slug: qs[:slug]) if qs[:slug].present?
    ds = ds.where(category: qs[:category]) if qs[:category].present?
    if qs[:search].present?
      term = "%#{qs[:search]}%"
      ds = ds.where(Sequel.like(:title, term, case_insensitive: true) | Sequel.like(:category, term, case_insensitive: true))
    end
    return_success(ds.all.map(&:to_pos))
  end
end
