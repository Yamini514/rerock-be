# The RAM Portal's own scoped slice of the CRM — the RAM's own assigned
# clients (needed so a RAM member has a real recipient list for
# services/ram_recommendations.rb), same "re-expose the admin table,
# filtered server-side to the authenticated identity" pattern as
# services/agent_portal.rb#my_clients, plus a create-only Leads endpoint
# (see create_my_lead below).
class App::Services::RamPortal < App::Services::Base
  def current_ram
    CurrentRam.ram_obj
  end

  def my_clients
    ram = current_ram
    return_errors!("Not signed in.", 401) if ram.nil?

    return_success(Client.where(assigned_ram_id: ram.slug).order(Sequel.desc(:created_at)).all.map(&:to_pos))
  end

  # "New Client" branch of RecommendPropertyModal.js — a brand-new contact
  # has no portal account yet, so there's no client_id a Recommendation
  # could attach to (see services/ram_recommendations.rb#create). This
  # captures them as a real Lead instead, same shape/ownership convention
  # as AgentPortal#create_my_site_visit: server-set ram_id, never trusted
  # from the client. Once this contact gets a client portal account, the
  # RAM can send them a real recommendation via the "Existing Client" path.
  #
  # Both phone and email are mandatory for this endpoint (spec change) —
  # Lead#validate already enforces client_phone's presence/format (it's also
  # a NOT NULL column, migrations/0014), so the explicit check below is what
  # additionally makes email mandatory here specifically.
  def create_my_lead
    ram = current_ram
    return_errors!("Not signed in.", 401) if ram.nil?
    return_errors!("Email is required.", 400) if params[:client_email].blank?
    return_errors!("An active lead for this phone number already exists.", 409) if Lead.duplicate_active?(params[:client_phone]&.strip)

    lead = Lead.new(
      client_name: params[:client_name]&.strip,
      client_phone: params[:client_phone]&.strip,
      client_email: params[:client_email]&.strip,
      # Optional — the Referrals page's "Refer a Client" flow lets a RAM
      # note which property the referred contact is interested in;
      # RecommendPropertyModal's "New Client" flow doesn't collect one, so
      # this stays nil there.
      property_id: params[:property_id].presence,
      source: params[:source].presence || "RAM",
      ram_id: ram.slug,
      status: "New"
    )

    save(lead) do |o|
      Notification.create(
        audience: "admin",
        type: "lead",
        icon: "UserPlus",
        title: "New lead captured",
        message: "#{ram.name} added a new lead: #{o.client_name}."
      )
      return_success(o.to_pos)
    end
  end

  # The RAM's own referral-program entries — real Referral rows
  # (services/referrals.rb, already admin-CRUD'd), scoped to this RAM via
  # `ram_id`. That column/filter already existed specifically for this
  # (see referrals.rb's own comment), just never had a RAM-facing route
  # until now. `reward`/`payout_status` are admin-set (a RAM setting their
  # own commission would be a business-logic hole), so they're read-only
  # here — visible on `mine`, never writable via create/update below.
  #
  # Each row is decorated with its linked Lead's real funnel stage/history
  # (Enquiry -> Qualified Lead -> Site Visit -> Negotiation -> Agreement ->
  # Closed, see models/lead.rb) so the RAM can see the standard flow their
  # referral is actually moving through, on top of the Referral's own
  # simpler Enquiry Stage/Site Visit Scheduled/Purchase Completed/Cancelled
  # status — reuses Lead#status_history as-is, no new history table.
  def my_referrals
    ram = current_ram
    return_errors!("Not signed in.", 401) if ram.nil?

    referrals = Referral.where(ram_id: ram.slug).order(Sequel.desc(:created_at)).all
    return_success(
      referrals.map do |referral|
        lead = referral.lead_id ? Lead[referral.lead_id] : nil
        row = referral.to_pos
        row.merge('leadStatus' => lead&.status, 'leadStatusHistory' => lead&.status_history || [])
      end
    )
  end

  # Read-only view of the Leads this RAM has personally sourced (via
  # create_my_referral/create_my_lead below) — same funnel/history as above,
  # exposed as its own list for a full "my leads" view rather than only
  # nested under referrals.
  def my_leads
    ram = current_ram
    return_errors!("Not signed in.", 401) if ram.nil?

    return_success(Lead.where(ram_id: ram.slug).order(Sequel.desc(:created_at)).all.map(&:with_status_history))
  end

  # RAM Dashboard's stat tiles — deliberately finance-free (contrast
  # services/ram_members.rb#stats, the admin RAM Details page's equivalent,
  # which includes revenue/commissionEarned). Every figure here is a plain
  # count derived from real, already-scoped tables — no new business logic:
  # `activeLeads` relies on the existing archived flag/TERMINAL_STATUSES
  # (services/leads.rb#sweep_expired_leads! already keeps `archived` correct
  # for the 60-day validity window), and `conversions` mirrors that same
  # Lead funnel's terminal success state.
  def my_stats
    ram = current_ram
    return_errors!("Not signed in.", 401) if ram.nil?

    referral_ds = Referral.where(ram_id: ram.slug)
    lead_ds = Lead.where(ram_id: ram.slug)

    return_success(
      'totalReferrals' => referral_ds.exclude(archived: true).count,
      'activeLeads' => lead_ds.where(archived: false).exclude(status: Lead::TERMINAL_STATUSES).count,
      'siteVisits' => SiteVisit.where(lead_id: lead_ds.select(:id)).count,
      'clients' => referral_ds.exclude(client_id: nil).select(:client_id).distinct.count,
      'conversions' => lead_ds.where(status: 'Closed').count
    )
  end

  # "Refer a Client" — the RAM personally sourcing a new prospect into the
  # business (as opposed to an existing client/agent referring someone,
  # which stays an admin-entered "Client Referral"/"Agent Referral" row).
  # The actual Lead+Referral creation (dedup, transaction, agent carry-over)
  # is the shared Base#create_referral_with_lead! — also used by
  # PublicContact/PublicSiteVisits when a visitor converts through this
  # RAM's own shared referral link instead of a direct manual entry here.
  def create_my_referral
    ram = current_ram
    return_errors!("Not signed in.", 401) if ram.nil?
    return_errors!("Referred person's email address is required.", 400) if params[:client_email].blank?

    # Referral Date and Time — defaults to now (same as before this field
    # existed) when the form leaves it blank; rejects a backdated timestamp
    # since it can't be used to log a referral earlier than when it's
    # actually being entered. A 60s grace window absorbs form-fill/network
    # latency between the picker's "now" and this request landing.
    referral_date = nil
    if params[:date].present?
      referral_date = begin
        Time.parse(params[:date].to_s)
      rescue ArgumentError, TypeError
        nil
      end
      return_errors!("Enter a valid referral date and time.", 400) if referral_date.nil?
      return_errors!("Referral date and time can't be in the past.", 400) if referral_date < Time.now - 60
    end

    lead, referral, property, agent_slug = create_referral_with_lead!(
      name: params[:referred]&.strip,
      phone: params[:client_phone]&.strip,
      email: params[:client_email]&.strip&.downcase,
      property_id: params[:property_id].presence,
      community_id: params[:community_id].presence,
      ram_id: ram.slug,
      referrer_name: ram.name,
      type: "RAM Referral",
      source: "RAM Referral",
      date: referral_date,
      note: params[:notes]&.strip.presence
    )

    agent_note = property.present? && agent_slug.blank? ? " No agent is assigned to this property yet — assignment required." : ""
    Notification.create(
      audience: "admin",
      type: "referral",
      icon: "Gift",
      title: "New referral",
      message: "#{ram.name} referred a new prospect: #{referral.referred}.#{agent_note}"
    )

    return_success(referral.to_pos.merge(lead: lead.to_pos))
  end

  # Status transitions only (Enquiry Stage -> Site Visit Scheduled ->
  # Purchase Completed/Cancelled) — same "the portal can move its own
  # record through the funnel, but never touch reward/payout" reasoning as
  # create above. notify_ram_of_status! is a no-op unless the new status is
  # one the RAM would want a nudge about (see models/referral.rb).
  def update_my_referral
    ram = current_ram
    return_errors!("Not signed in.", 401) if ram.nil?

    referral = Referral[rp[:id]]
    return_errors!("Referral not found.", 404) if referral.nil?
    return_errors!("This referral isn't yours.", 403) unless referral.ram_id == ram.slug

    allowed = params.slice(:status)
    referral.set_fields(allowed, allowed.keys)
    save(referral) do |o|
      o.notify_ram_of_status!
      return_success(o.to_pos)
    end
  end

  # Read-only — reward/payout/status transitions all stay admin-only via
  # services/commissions.rb; this just re-exposes the RAM's own slice of
  # that real table, same convention as my_referrals/my_clients above.
  def my_commissions
    ram = current_ram
    return_errors!("Not signed in.", 401) if ram.nil?

    return_success(Commission.where(ram_id: ram.slug).order(Sequel.desc(:created_at)).all.map(&:to_pos))
  end

  # Read-only — the RAM's own site visits. `site_visits` has no `ram_id`
  # column (only `agent_slug`, see migrations/0015), so this scopes through
  # the visit's Lead instead — the same subquery `my_stats`' `siteVisits`
  # count already uses (see #my_stats above). Status transitions
  # (Scheduled/Completed/Cancelled/Rescheduled) stay agent/admin-only, same
  # "the portal can see its own record but not run the visit" reasoning as
  # my_commissions above.
  def my_site_visits
    ram = current_ram
    return_errors!("Not signed in.", 401) if ram.nil?

    return_success(
      SiteVisit.where(lead_id: Lead.where(ram_id: ram.slug).select(:id)).order(Sequel.desc(:created_at)).all.map(&:to_pos)
    )
  end
end
