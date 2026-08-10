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
    referral_code = params[:referral_code]&.strip

    return_errors!("Name is required.", 400) if name.blank?
    return_errors!("A phone number or email is required.", 400) if phone.blank? && email.blank?
    return_errors!("Message is required.", 400) if message.blank?

    note = [interest.presence, message].compact.join(" — ")
    link = referral_code.present? ? ReferralLink.where(code: referral_code, active: true).first : nil

    # A visitor who arrived via a RAM's referral link gets attributed —
    # Base#create_referral_with_lead! needs at least a phone number
    # (same requirement as its own Lead), so an email-only submission
    # still falls through to the plain, unattributed path below rather
    # than hard-failing an enquiry that would otherwise have gone through.
    if link && phone.present?
      ram = RamMember.where(slug: link.ram_id).first
      lead, = create_referral_with_lead!(
        name: name, phone: phone, email: email, property_id: link.property_id,
        ram_id: link.ram_id, referrer_name: ram&.name || "Referral Link",
        type: "Referral Link", source: "Referral Link", referral_link_id: link.id
      )
      lead.timeline = [{ type: "Note", note: note, date: Time.now.strftime("%Y-%m-%d") }]
      lead.save(validate: false)

      Notification.create(
        audience: "admin",
        type: "referral",
        icon: "Gift",
        title: "New referral",
        message: "#{ram&.name || 'A referral link'} brought in a new prospect: #{name}."
      )
      return_success("Thanks! An advisor will get back to you within 2 hours.")
    else
      lead = Lead.new(
        client_name: name,
        client_phone: phone,
        client_email: email,
        source: "Website",
        priority: "Medium",
        status: "New",
        timeline: [{ type: "Note", note: note, date: Time.now.strftime("%Y-%m-%d") }]
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
end
