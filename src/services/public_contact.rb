# Unauthenticated public contact-form submission. Used to create a real
# Lead (source: "Website"), mixing every "just asking a question" message
# into the same CRM/Enquiries pipeline as actual sales prospects — and, if
# the visitor arrived via a RAM referral link, a Referral on top of that
# for commission tracking. Both are gone now (business decision): this
# form is a lightweight inbox (see App::Models::ContactMessage /
# services/contact_messages.rb), not a Lead-generation flow, full stop —
# including for referral-attributed visitors. Base#create_referral_with_lead!
# is untouched and still used by BookVisitModal / RAM Portal's own referral
# capture; this service just no longer calls it.
class App::Services::PublicContact < App::Services::Base
  def model; ContactMessage; end

  def create
    name = params[:name]&.strip
    phone = params[:phone]&.strip
    email = params[:email]&.strip&.downcase
    message = params[:message]&.strip
    referral_code = params[:referral_code]&.strip

    return_errors!("Name is required.", 400) if name.blank?
    return_errors!("A phone number or email is required.", 400) if phone.blank? && email.blank?
    return_errors!("Message is required.", 400) if message.blank?

    contact_message = ContactMessage.new(
      name: name,
      phone: phone,
      email: email,
      message: message,
      referral_code: referral_code
    )
    save(contact_message) do
      Notification.create(
        audience: "admin",
        type: "enquiry",
        icon: "Mail",
        title: "New contact message",
        message: "#{name} sent a message through the site's Contact form."
      )
      return_success("Thanks! An advisor will get back to you within 2 hours.")
    end
  end
end
