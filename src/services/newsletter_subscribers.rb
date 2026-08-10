# Admin-facing view over newsletter subscribers. No admin `create` — a
# subscriber row only ever originates from a real public subscription (see
# services/public_newsletter.rb), same reasoning as JobApplications.
class App::Services::NewsletterSubscribers < App::Services::Base
  def model; NewsletterSubscriber; end

  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    return_success(ds.all.map(&:to_pos))
  end

  def self.fields
    { save: [:status] }
  end
end
