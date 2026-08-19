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
    referral_code = params[:referral_code]&.strip
    # BookVisitModal.js's guest form didn't collect this at all before —
    # every guest-booked visit created a Lead that silently looked like a
    # ₹0-budget prospect to whichever agent picked it up, same gap as the
    # authenticated Client Portal flow (services/client_site_visits.rb).
    budget = params[:budget].present? ? params[:budget].to_i : 0

    return_errors!("Name is required.", 400) if name.blank?
    return_errors!("Phone number is required.", 400) if phone.blank?
    return_errors!("Preferred date is required.", 400) if date.blank?

    # Nothing stopped a guest (or a stale/replayed form) from submitting an
    # already-past date, or from typing something that isn't a real date at
    # all — this form has no server-side date validation whatsoever before
    # now.
    begin
      parsed_date = Date.parse(date)
    rescue ArgumentError, TypeError
      return_errors!("Preferred date is invalid.", 400)
    end
    return_errors!("Preferred date can't be in the past.", 400) if parsed_date < Date.today

    property = property_slug.present? ? Property.first(slug: property_slug) : nil

    # A guest who already has an open enquiry (from an earlier site-visit
    # request, brochure download, etc.) used to get hard-blocked here with a
    # 409 on every repeat submission for the same phone number — including a
    # second, different-date/different-slot visit request made *after*
    # their first one had already been confirmed — until the original Lead
    # reached Closed/Lost or its own 60-day validity window lapsed
    # (Lead::VALIDITY_DAYS). Reuse that existing Lead for the new SiteVisit
    # instead: still one real contact, still protected against a
    # double-click/refresh spawning a duplicate Lead (see Lead#active_for_phone),
    # but no longer wrongly blocking a legitimate repeat visitor. Referral
    # attribution only ever applies to a brand-new Lead (see
    # Base#create_referral_with_lead!'s own "first accepted referral owns
    # the customer" rule), so a repeat guest's referral_code, if any, is
    # ignored here — same reasoning services/client_site_visits.rb#create
    # already uses to drop a link once a client has an active referral.
    existing_lead = Lead.active_for_phone(phone)
    return finalize_site_visit!(existing_lead, property, name, date, time) if existing_lead

    link = referral_code.present? ? ReferralLink.where(code: referral_code, active: true).first : nil

    if link
      ram = RamMember.where(slug: link.ram_id).first
      lead, = create_referral_with_lead!(
        name: name, phone: phone, email: nil,
        property_id: property&.id || link.property_id,
        ram_id: link.ram_id, referrer_name: ram&.name || "Referral Link",
        type: "Referral Link", source: "Referral Link", referral_link_id: link.id,
        budget: budget
      )
      notify_safely!(
        audience: "admin",
        type: "referral",
        icon: "Gift",
        title: "New referral",
        message: "#{ram&.name || 'A referral link'} brought in a new prospect: #{name}."
      )
      finalize_site_visit!(lead, property, name, date, time)
    else
      lead = Lead.new(
        client_name: name,
        client_phone: phone,
        property_id: property&.id,
        agent_slug: property&.agent_slug,
        source: "Website",
        priority: "Medium",
        status: "New",
        budget: budget,
        timeline: [{ type: "Note", note: "Requested a site visit#{property_title.present? ? " for #{property_title}" : ""}.", date: Time.now.strftime("%Y-%m-%d") }]
      )
      save(lead) { |saved_lead| finalize_site_visit!(saved_lead, property, name, date, time) }
    end
  end

  private

  def finalize_site_visit!(lead, property, name, date, time)
    visit = SiteVisit.new(
      lead_id: lead.id,
      property_id: property&.id,
      community_id: property&.community_id,
      client_name: name,
      agent_slug: property&.agent_slug,
      date: date,
      time: time,
      status: "Pending"
    )

    save(visit) do
      notify_safely!(
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
