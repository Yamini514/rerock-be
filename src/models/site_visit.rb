class App::Models::SiteVisit < Sequel::Model
  many_to_one :lead
  many_to_one :property
  many_to_one :community

  # Called after every save from both the admin (services/site_visits.rb)
  # and agent-portal (services/agent_portal.rb#update_my_site_visit) update
  # paths. Idempotent — the `Deal.where(site_visit_id: id).first` guard
  # means a re-save of an already-Completed visit (e.g. editing notes
  # afterward) never creates a second Deal. Seeds the Deal's own `notes`
  # from the visit's notes as a starting point; from there it's an
  # independent, directly-editable field (see services/deals.rb).
  def ensure_deal_for_completion!
    return unless status == 'Completed'
    return if App::Models::Deal.where(site_visit_id: id).first

    # Real Referral that produced this visit's Lead, if any (Referral#lead_id
    # — migrations/0059) — carried onto the new Deal so
    # Deal#ensure_commission_for_closure! has something to compute a
    # commission against once this deal eventually closes.
    referral = lead_id ? App::Models::Referral.where(lead_id: lead_id).first : nil

    App::Models::Deal.create(
      site_visit_id: id,
      client_id: lead&.client_id,
      client_name: client_name,
      property_id: property_id,
      property_name: property&.title,
      agent_slug: agent_slug,
      referral_id: referral&.id,
      stage: 'Opportunity',
      notes: notes
    )
  end

  # Called after every save from both the admin (services/site_visits.rb)
  # and agent-portal (services/agent_portal.rb#update_my_site_visit) update
  # paths, same "explicit call after save, guarded by an actual-change
  # check" convention as Referral/Commission#notify_*_of_status!. Only the
  # three transitions a client would actually want an unprompted nudge
  # about — initial scheduling is already covered by AgentPortal's own
  # "Site visit scheduled" notification at creation time, and ClientSiteVisits
  # doesn't need one at all since the client just did the scheduling
  # themselves. No client to notify at all for a guest-sourced visit (no
  # `lead.client_id`) or when the visit's client never got a portal account.
  def notify_client_of_status!
    return unless column_changed?(:status)
    return unless %w[Cancelled Rescheduled Completed].include?(status)

    client = lead&.client
    return if client.nil?

    where = property.present? ? " for #{property.title}" : ""
    copy = {
      'Cancelled' => ['Site visit cancelled', "Your site visit#{where} on #{date} has been cancelled."],
      'Rescheduled' => ['Site visit rescheduled', "Your site visit#{where} has been rescheduled to #{date}#{time.present? ? " at #{time}" : ""}."],
      'Completed' => ['Site visit completed', "Your site visit#{where} is complete. We'll follow up with next steps shortly."],
    }[status]

    App::Models::Notification.create(
      audience: 'client',
      recipient_id: client.id,
      type: 'visit',
      icon: status == 'Cancelled' ? 'XCircle' : (status == 'Rescheduled' ? 'CalendarClock' : 'CalendarCheck'),
      title: copy[0],
      message: copy[1]
    )
  end
end
