# Authenticated Client Portal "Book a Site Visit" submission — the
# logged-in-client counterpart to services/public_site_visits.rb's guest
# flow. A verified client's request doesn't need an admin approval gate the
# way a guest's does: it lands straight as "Scheduled" and connects both the
# property's agent (if resolvable) and the admin, per BookVisitModal's
# client-portal branch (client is already known, not re-collected).
class App::Services::ClientSiteVisits < App::Services::Base
  def model; SiteVisit; end

  def create
    client = CurrentClient.client_obj
    return_errors!("Not signed in.", 401) if client.nil?

    date = params[:date]&.strip
    time = params[:time]&.strip
    property_slug = params[:property_slug]&.strip
    property_title = params[:property_title]&.strip

    return_errors!("Preferred date is required.", 400) if date.blank?

    property = property_slug.present? ? Property.first(slug: property_slug) : nil

    lead = Lead.new(
      client_id: client.id,
      client_name: client.name,
      client_phone: client.phone,
      client_email: client.email,
      property_id: property&.id,
      agent_slug: property&.agent_slug,
      source: "Client Portal",
      priority: "Medium",
      status: "New",
      timeline: [{ type: "Note", note: "Requested a site visit#{property_title.present? ? " for #{property_title}" : ""}.", date: Time.now.strftime("%Y-%m-%d") }]
    )

    save(lead) do |saved_lead|
      visit = SiteVisit.new(
        lead_id: saved_lead.id,
        property_id: property&.id,
        community_id: property&.community_id,
        client_name: client.name,
        agent_slug: property&.agent_slug,
        date: date,
        time: time,
        status: "Scheduled"
      )

      save(visit) do
        Notification.create(
          audience: "admin",
          type: "visit",
          icon: "CalendarCheck",
          title: "New site visit request",
          message: "#{client.name} requested a visit#{property ? " for #{property.title}" : ""}."
        )

        agent = property&.agent_slug.present? ? Agent.first(slug: property.agent_slug) : nil
        if agent
          Notification.create(
            audience: "agent",
            recipient_id: agent.id,
            type: "visit",
            icon: "CalendarCheck",
            title: "New site visit request",
            message: "#{client.name} requested a visit#{property ? " for #{property.title}" : ""}."
          )
        end

        return_success("Your site visit has been requested. An advisor will confirm shortly.")
      end
    end
  end

  # The client's own scheduled/past site visits — replaces
  # SiteVisitsClient.js's old local-only mock (lib/data/portalSiteVisits.js).
  # SiteVisit only stores property_id/agent_slug (models/site_visit.rb), so
  # this joins in the property's title/slug/area and the assigned
  # agent's name rather than pushing that lookup onto the frontend.
  def mine
    client = CurrentClient.client_obj
    return_errors!("Not signed in.", 401) if client.nil?

    lead_ids = Lead.where(client_id: client.id).select(:id)
    visits = SiteVisit.where(lead_id: lead_ids).order(Sequel.desc(:date), Sequel.desc(:created_at)).all
    return_success(visits.map { |v| visit_brief(v) })
  end

  private

  def visit_brief(visit)
    property = visit.property
    agent = visit.agent_slug.present? ? Agent.first(slug: visit.agent_slug) : nil
    {
      'id' => visit.id,
      'property_title' => property&.title,
      'property_slug' => property&.slug,
      'location' => property&.area&.name,
      'advisor_name' => agent&.name,
      'date' => visit.date,
      'time' => visit.time,
      'status' => visit.status,
    }
  end
end
