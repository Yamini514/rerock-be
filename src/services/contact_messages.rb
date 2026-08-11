# Admin-facing inbox over public Contact form submissions. No admin
# `create` — a row only ever originates from a real public submission (see
# services/public_contact.rb), same reasoning as NewsletterSubscribers/
# JobApplications. The only thing an admin can change is the read flag;
# there's no status workflow here on purpose — anything that needs real
# follow-up tracking belongs in Leads (Admin > Enquiries), not this inbox.
class App::Services::ContactMessages < App::Services::Base
  def model; ContactMessage; end

  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(read: qs[:read].to_s == 'true') if qs.key?(:read)
    if qs[:search].present?
      term = "%#{qs[:search]}%"
      ds = ds.where(
        Sequel.like(:name, term, case_insensitive: true) |
        Sequel.like(:email, term, case_insensitive: true) |
        Sequel.like(:message, term, case_insensitive: true)
      )
    end
    return_success(ds.all.map(&:to_pos))
  end

  def self.fields
    { save: [:read] }
  end
end
