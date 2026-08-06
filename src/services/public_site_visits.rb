# Unauthenticated public "Book a Site Visit" submission (guest/not-logged-in
# visitors only — a logged-in client uses services/client_site_visits.rb
# instead) — creates a real Lead + SiteVisit (source: "Website") instead of
# BookVisitModal's old toast-only fake submit. `site_visits` has no
# phone/email column of its own (see migrations/0015's own comment: a visit
# is "booked against a lead"), so this creates the Lead first and links the
# SiteVisit to it, same as an admin manually logging a walk-in visit would.
# Mirrors services/public_contact.rb's validation style. Lands as "Pending"
# rather than "Scheduled" — an unverified guest's request needs an admin to
# confirm it before it's a real appointment.
class App::Services::PublicSiteVisits < App::Services::Base
  def model; SiteVisit; end

  def create
    name = params[:name]&.strip
    phone = params[:phone]&.strip
    date = params[:date]&.strip
    time = params[:time]&.strip
    property_slug = params[:property_slug]&.strip
    property_title = params[:property_title]&.strip

    return_errors!("Name is required.", 400) if name.blank?
    return_errors!("Phone number is required.", 400) if phone.blank?
    return_errors!("Preferred date is required.", 400) if date.blank?

    property = property_slug.present? ? Property.first(slug: property_slug) : nil

    lead = Lead.new(
      client_name: name,
      client_phone: phone,
      property_id: property&.id,
      agent_slug: property&.agent_slug,
      source: "Website",
      priority: "Medium",
      status: "New",
      timeline: [{ type: "Note", note: "Requested a site visit#{property_title.present? ? " for #{property_title}" : ""}.", date: Time.now.strftime("%Y-%m-%d") }]
    )

    save(lead) do |saved_lead|
      visit = SiteVisit.new(
        lead_id: saved_lead.id,
        property_id: property&.id,
        community_id: property&.community_id,
        client_name: name,
        agent_slug: property&.agent_slug,
        date: date,
        time: time,
        status: "Pending"
      )

      save(visit) do
        Notification.create(
          audience: "admin",
          type: "visit",
          icon: "CalendarCheck",
          title: "New site visit request",
          message: "#{name} requested a visit#{property ? " for #{property.title}" : ""} — awaiting approval."
        )
        return_success("Your site visit has been requested. An advisor will confirm shortly.")
      end
    end
  end
end
