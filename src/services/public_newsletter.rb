require 'uri'

# Unauthenticated public newsletter subscription — validates the email,
# rejects a duplicate with a friendly error (same "already exists" phrasing
# convention as RamAuth#register/ClientAuth#register), else creates the row.
class App::Services::PublicNewsletter < App::Services::Base
  def model; NewsletterSubscriber; end

  def create
    email = params[:email]&.strip&.downcase

    return_errors!("Enter a valid email address.", 400) if email.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)
    return_errors!("This email is already subscribed.", 400) if NewsletterSubscriber.where(email: email).first

    subscriber = NewsletterSubscriber.new(email: email, status: 'Subscribed', source: 'Website')
    save(subscriber) { return_success("You're subscribed!") }
  end
end
