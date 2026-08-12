# Admin-facing view over newsletter subscribers. No admin `create` — a
# subscriber row only ever originates from a real public subscription (see
# services/public_newsletter.rb), same reasoning as JobApplications.
class App::Services::NewsletterSubscribers < App::Services::Base
  def model; NewsletterSubscriber; end

  SORTABLE_COLUMNS = %w[email created_at status].freeze

  def list
    ds = model
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    if qs[:search].present?
      ds = ds.where(Sequel.like(:email, "%#{qs[:search]}%", case_insensitive: true))
    end
    ds = apply_sort(ds, SORTABLE_COLUMNS, default: [[:created_at, :desc]])
    paginated_response(ds)
  end

  def self.fields
    { save: [:status] }
  end
end
