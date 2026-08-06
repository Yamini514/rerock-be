# Unauthenticated public contact-form submission — creates a real Lead
# (source: "Website") instead of the old frontend-only fake toast. Reuses
# the exact same Lead model/table the Admin Portal's Enquiries page already
# manages (services/leads.rb) rather than a separate "contact messages"
# concept.
class App::Services::PublicContact < App::Services::Base
  def model; Lead; end

  def create
    name = params[:name]&.strip
    phone = params[:phone]&.strip
    email = params[:email]&.strip&.downcase
    message = params[:message]&.strip
    interest = params[:interest]&.strip

    return_errors!("Name is required.", 400) if name.blank?
    return_errors!("A phone number or email is required.", 400) if phone.blank? && email.blank?
    return_errors!("Message is required.", 400) if message.blank?

    lead = Lead.new(
      client_name: name,
      client_phone: phone,
      client_email: email,
      source: "Website",
      priority: "Medium",
      status: "New",
      timeline: [{ type: "Note", note: [interest.presence, message].compact.join(" — "), date: Time.now.strftime("%Y-%m-%d") }]
    )
    save(lead) do
      Notification.create(
        audience: "admin",
        type: "enquiry",
        icon: "Mail",
        title: "New enquiry",
        message: "#{name} submitted an enquiry#{interest.present? ? " about #{interest}" : ""}."
      )
      return_success("Thanks! An advisor will get back to you within 2 hours.")
    end
  end
end
