# Unauthenticated, read-only — only "Approved" testimonials, regardless of
# any query param. Same forced-status-server-side pattern as PublicReviews.
# This is also the exact feed the homepage carousel renders (no other public
# consumer exists), so `show_on_homepage` is filtered here too — the admin's
# per-testimonial "Show on Homepage" toggle IS the homepage curation.
class App::Services::PublicTestimonials < App::Services::Base
  def model; Testimonial; end

  def list
    return_success(model.where(status: 'Approved', show_on_homepage: true).order(Sequel.desc(:created_at), Sequel.desc(:id)).all.map(&:to_pos))
  end
end
