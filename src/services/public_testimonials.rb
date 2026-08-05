# Unauthenticated, read-only — only "Approved" testimonials, regardless of
# any query param. Same forced-status-server-side pattern as PublicReviews.
class App::Services::PublicTestimonials < App::Services::Base
  def model; Testimonial; end

  def list
    return_success(model.where(status: 'Approved').order(Sequel.desc(:created_at), Sequel.desc(:id)).all.map(&:to_pos))
  end
end
