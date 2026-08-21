# Unauthenticated public "Download a Brochure/Plan" lead-gate submission —
# creates a real Lead (source: "Brochure Download") tied to the community,
# same shape/spirit as services/public_site_visits.rb's guest flow, minus
# the SiteVisit half (a brochure request never books an appointment). A
# logged-in client instead uses services/client_brochure_requests.rb and
# skips this form entirely (see BrochureRequestModal.js).
class App::Services::PublicBrochureRequests < App::Services::Base
  def model; Lead; end

  def create
    name = params[:name]&.strip
    phone = params[:phone]&.strip
    email = params[:email]&.strip
    community_id = params[:community_id]
    document_name = params[:document_name]&.strip
    referral_code = params[:referral_code]&.strip

    return_errors!("Name is required.", 400) if name.blank?
    return_errors!("Phone number is required.", 400) if phone.blank?
    return_errors!("Community is required.", 400) if community_id.blank?

    community = Community[community_id]
    return_errors!("Community not found.", 404) if community.nil?

    link = referral_code.present? ? ReferralLink.where(code: referral_code, active: true).first : nil

    if link
      # A link is owned by exactly one of a RAM member or a Client
      # (models/referral_link.rb#validate) — resolve whichever one it is,
      # same branching as services/public_referral_links.rb#click.
      if link.ram_id.present?
        referrer_name = RamMember.where(slug: link.ram_id).first&.name || "Referral Link"
        ram_id = link.ram_id
        referrer_client_id = nil
      else
        referrer_name = Client[link.client_id]&.name || "Referral Link"
        ram_id = nil
        referrer_client_id = link.client_id
      end

      lead, = create_referral_with_lead!(
        name: name, phone: phone, email: email.presence,
        property_id: nil, ram_id: ram_id, referrer_client_id: referrer_client_id,
        referrer_name: referrer_name, type: "Referral Link", source: "Referral Link", referral_link_id: link.id
      )
      Notification.create(
        audience: "admin",
        type: "referral",
        icon: "Gift",
        title: "New referral",
        message: "#{referrer_name} brought in a new prospect: #{name}."
      )
      finalize_brochure_request!(lead, community, name, document_name)
    else
      lead = Lead.new(
        client_name: name,
        client_phone: phone,
        client_email: email.presence,
        community_id: community.id,
        source: "Brochure Download",
        priority: "Medium",
        status: "Enquiry",
        timeline: [{ type: "Note", note: brochure_note(community, document_name), date: Time.now.strftime("%Y-%m-%d") }]
      )
      save(lead) { finalize_brochure_request!(lead, community, name, document_name) }
    end
  end

  private

  def brochure_note(community, document_name)
    "Requested brochure#{document_name.present? ? ": #{document_name}" : ""} for #{community.name}."
  end

  def finalize_brochure_request!(lead, community, name, document_name)
    # Referral-attributed leads arrive here without the community_id/note the
    # non-referral branch above already set at creation — `create_referral_with_lead!`
    # has no `community_id:` keyword of its own (it's shared by callers that
    # aren't community-scoped), so this backfills both in one extra save
    # rather than widening that shared helper's signature for one caller.
    if lead.community_id != community.id || lead.timeline.blank?
      lead.update(community_id: community.id, timeline: (lead.timeline || []) + [{ type: "Note", note: brochure_note(community, document_name), date: Time.now.strftime("%Y-%m-%d") }])
    end

    Notification.create(
      audience: "admin",
      type: "lead",
      icon: "FileText",
      title: "New brochure request",
      message: "#{name} requested a brochure for #{community.name}."
    )
    return_success("You're all set — your download will begin shortly.")
  end
end
