# Authenticated Client Portal "Download a Brochure/Plan" submission — the
# logged-in-client counterpart to services/public_brochure_requests.rb's
# guest flow. A verified client is already known (name/phone/email come from
# the session, never re-collected), so BrochureRequestModal.js skips its own
# form entirely for a logged-in client and calls this directly.
class App::Services::ClientBrochureRequests < App::Services::Base
  def model; Lead; end

  def create
    client = CurrentClient.client_obj
    return_errors!("Not signed in.", 401) if client.nil?
    # Same gap/guard as services/client_site_visits.rb#create — this Lead
    # also hard-requires client_phone (models/lead.rb).
    return_errors!("Add a phone number to your profile before requesting a brochure.", 400) if client.phone.blank?

    community_id = params[:community_id]
    document_name = params[:document_name]&.strip
    return_errors!("Community is required.", 400) if community_id.blank?

    community = Community[community_id]
    return_errors!("Community not found.", 404) if community.nil?

    lead = Lead.new(
      client_id: client.id,
      client_name: client.name,
      client_phone: client.phone,
      client_email: client.email,
      community_id: community.id,
      source: "Client Portal",
      priority: "Medium",
      status: "Enquiry",
      timeline: [{ type: "Note", note: "Requested brochure#{document_name.present? ? ": #{document_name}" : ""} for #{community.name}.", date: Time.now.strftime("%Y-%m-%d") }]
    )

    save(lead) do
      Notification.create(
        audience: "admin",
        type: "lead",
        icon: "FileText",
        title: "New brochure request",
        message: "#{client.name} requested a brochure for #{community.name}."
      )
      return_success("Download starting…")
    end
  end
end
