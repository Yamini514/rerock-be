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
    # A site visit's Lead hard-requires client_phone (models/lead.rb's
    # validates_presence) — client.phone can be blank if the client cleared
    # it via their own profile (client_auth.rb#update_profile has no
    # presence guard on phone the way name/email do). Catching it here with
    # an actionable message instead of letting the Lead#validate failure
    # below surface as a generic "couldn't schedule visit" error.
    return_errors!("Add a phone number to your profile before booking a site visit.", 400) if client.phone.blank?

    date = params[:date]&.strip
    time = params[:time]&.strip
    property_slug = params[:property_slug]&.strip
    property_title = params[:property_title]&.strip
    referral_code = params[:referral_code]&.strip
    # BookVisitModal.js's client form didn't collect this at all before —
    # same gap as the guest flow (services/public_site_visits.rb).
    budget = params[:budget].present? ? params[:budget].to_i : 0

    return_errors!("Preferred date is required.", 400) if date.blank?

    property = property_slug.present? ? Property.first(slug: property_slug) : nil

    # A client who already owns this property (Client#invested_properties,
    # migrations/0017) has nothing left to decide by touring it again —
    # nothing stopped them from re-booking a site visit on a property
    # they'd already purchased. Same "does this client own this property"
    # check services/client_reviews.rb already uses to gate a Property
    # review, now shared on the model (Client#owned_property_ids) instead
    # of staying duplicated.
    if property && client.owned_property_ids.include?(property.id)
      return_errors!("You already own this property — no need to schedule another visit.", 400)
    end

    # models/site_visit.rb's own validate already rejects this too (same
    # rule, single source of truth) — checked again here, with a real
    # message, purely because a Hash-shaped model-validation error doesn't
    # surface readably through clientApiClient.js (it falls back to a bare
    # "Request failed"), unlike the admin's own apiClient.js which already
    # flattens those. Same reasoning as the phone-number guard above.
    if time.present? && has_conflicting_visit?(client.phone, date, time)
      return_errors!("You already have a site visit booked for this exact date and time.", 400)
    end

    # A logged-in client can still be the same person who clicked a RAM's
    # shared referral link this session (BookVisitModal.js sends the code
    # regardless of login state) — attribute it the same way
    # public_site_visits.rb does for guests, but best-effort: an invalid/
    # inactive code, or a client who already has an active referral ("first
    # accepted referral owns the customer" — see Base#create_referral_with_lead!),
    # just means no Referral gets created. It never blocks the visit request
    # itself, unlike the guest flow's hard 409 on a duplicate active referral.
    link = referral_code.present? ? ReferralLink.where(code: referral_code, active: true).first : nil
    if link && Referral.where(client_id: client.id, archived: false).exclude(status: ["Purchase Completed", "Cancelled"]).first
      link = nil
    end

    lead = Lead.new(
      client_id: client.id,
      client_name: client.name,
      client_phone: client.phone,
      client_email: client.email,
      property_id: property&.id,
      agent_slug: property&.agent_slug,
      ram_id: link&.ram_id,
      source: link ? "Referral Link" : "Client Portal",
      priority: "Medium",
      status: "New",
      budget: budget,
      timeline: [{ type: "Note", note: "Requested a site visit#{property_title.present? ? " for #{property_title}" : ""}.", date: Time.now.strftime("%Y-%m-%d") }]
    )

    save(lead) do |saved_lead|
      # Referral attribution here is supplementary to the visit the client
      # actually asked to book — it must never be able to fail the request
      # over something in this optional side path, especially now that
      # Base#save's own rescue only guards the object it was actually asked
      # to save (see that method's comment): an unrescued exception here
      # would otherwise propagate raw past the already-committed Lead.
      if link
        begin
          ram = RamMember.where(slug: link.ram_id).first
          referral = Referral.new(
            ram_id: link.ram_id,
            type: "Referral Link",
            referrer: ram&.name || "Referral Link",
            referred: client.name,
            client_id: client.id,
            property_id: property&.id,
            lead_id: saved_lead.id,
            referral_link_id: link.id,
            status: "Enquiry Stage",
            reward: 0,
            date: Time.now
          )
          if referral.valid?
            referral.save(validate: false)
            write_audit_log!(referral, true)
          end
        rescue => e
          App.logger.error("[Referral] create failed for lead ##{saved_lead.id}: #{e.message}")
          App.logger.error(e.backtrace)
        end
      end

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
        notify_safely!(
          audience: "admin",
          type: "visit",
          icon: "CalendarCheck",
          title: "New site visit request",
          message: "#{client.name} requested a visit#{property ? " for #{property.title}" : ""}."
        )

        agent = property&.agent_slug.present? ? Agent.first(slug: property.agent_slug) : nil
        if agent
          notify_safely!(
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

  # Same person (by phone), same exact date+time, an already-active
  # appointment — see models/site_visit.rb's own validate for the full
  # reasoning (scoped by client_phone rather than lead_id since this flow
  # creates a brand-new Lead on every single booking).
  def has_conflicting_visit?(phone, date, time)
    lead_ids = Lead.where(client_phone: phone).select(:id)
    SiteVisit.where(lead_id: lead_ids, date: date, time: time).exclude(status: 'Cancelled').first.present?
  end

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
