require 'uri'

# Unauthenticated public newsletter subscription — validates the email,
# rejects a duplicate with a friendly error (same "already exists" phrasing
# convention as RamAuth#register/ClientAuth#register), else creates the row.
class App::Services::PublicNewsletter < App::Services::Base
  def model; NewsletterSubscriber; end

  def create
    email = params[:email]&.strip&.downcase

    return_errors!("Enter a valid email address.", 400) if email.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)

    existing = NewsletterSubscriber.where(email: email).first
    if existing
      return_errors!("This email is already subscribed.", 400) if existing.status == 'Subscribed'

      # Previously unsubscribed — re-subscribing should actually work rather
      # than permanently dead-ending on "already subscribed" forever (the old
      # check here only looked at row existence, never `status`, so anyone
      # who unsubscribed had no way back in through this same form).
      existing.status = 'Subscribed'
      return save(existing) { return_success("You're subscribed!") }
    end

    subscriber = NewsletterSubscriber.new(email: email, status: 'Subscribed', source: 'Website')
    save(subscriber) { return_success("You're subscribed!") }
  end

  # Self-service unsubscribe — previously the *only* way a subscriber's
  # status could change was an admin manually flipping it from
  # /admin/newsletter-subscribers (services/newsletter_subscribers.rb); the
  # subscriber themselves had no way to act on the Footer's own "Unsubscribe
  # anytime" promise. No token/auth: same low-stakes, email-only model the
  # rest of this feature already uses (no real campaign-email sending exists
  # yet to deliver a signed unsubscribe link into, unlike e.g. password
  # reset's real token flow) — an email that was never subscribed, or is
  # already unsubscribed, still gets a clean success message rather than an
  # error, so this is safe to call idempotently/repeatedly.
  def unsubscribe
    email = params[:email]&.strip&.downcase
    return_errors!("Enter a valid email address.", 400) if email.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)

    subscriber = NewsletterSubscriber.where(email: email).first
    return return_success("That email wasn't on our newsletter list.") if subscriber.nil?
    return return_success("You're already unsubscribed.") if subscriber.status == 'Unsubscribed'

    subscriber.status = 'Unsubscribed'
    save(subscriber) { return_success("You've been unsubscribed. Sorry to see you go!") }
  end
end
