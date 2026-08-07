class App::Models::Lead < Sequel::Model
  many_to_one :property
  many_to_one :community
  many_to_one :area
  many_to_one :client

  EMAIL_REGEXP = /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/

  # Defense-in-depth under the admin "Log Enquiry" form's / public contact
  # form's / client-portal enquiry form's own client-side checks — a direct
  # API call bypasses those entirely today. `client_email` stays optional
  # (a walk-in lead may only have a phone number) but is format-checked
  # when present; note the Won->Client auto-conversion flow
  # (services/leads.rb#update) has its own, stricter "email required to
  # convert" gate — that's a business-flow rule, not a data-shape one, so it
  # lives in the service, not here.
  def validate
    super
    validates_presence [:client_name, :client_phone]
    validates_format(EMAIL_REGEXP, :client_email, message: 'is not a valid email address') if client_email.present?
    errors.add(:client_phone, 'must be a 10-digit phone number') if client_phone.present? && client_phone.gsub(/\D/, '').length != 10
  end
end
