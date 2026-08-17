class App::Models::SiteVisit < Sequel::Model
  many_to_one :lead
  many_to_one :property
  many_to_one :community

  # Mirrors lib/data/siteVisits.js's SITE_VISIT_STATUSES / services/
  # site_visits.rb#update's own comment ("Scheduled -> Completed/
  # Cancelled/Rescheduled"), PLUS 'Pending' — the initial state
  # services/public_site_visits.rb creates a guest-submitted visit request
  # in, before an admin has confirmed it (not in the admin dropdown's own
  # enum, since an admin never *sets* Pending by hand, but a real value this
  # model must still accept on create). This model had NO validation at all
  # before — a typo'd or malformed status saved silently, and since both
  # hooks below key off an exact string match (`status == 'Completed'`,
  # `%w[Cancelled Rescheduled Completed].include?(status)`), a bad value
  # would quietly skip Deal auto-creation and the client notification with
  # no error anywhere to explain why. Same "must be one of" convention as
  # Community#status/Lead#status.
  STATUSES = ['Pending', 'Scheduled', 'Completed', 'Cancelled', 'Rescheduled'].freeze

  def validate
    super
    errors.add(:status, "must be one of #{STATUSES.join(', ')}") if status.present? && !STATUSES.include?(status)

    # Nothing stopped a visit dated next week from being marked Completed
    # today — which would also wrongly fire ensure_deal_for_completion!
    # below for a visit that hasn't actually happened yet. Scoped to
    # `new? || column_changed?(:status)` (same convention as Community's
    # cross-field checks) so an unrelated edit to an already-Completed
    # legacy row with a since-adjusted date doesn't suddenly start failing.
    # A same-day visit is allowed to be marked Completed (the appointment
    # may already be over by the time it's logged) — only a genuinely
    # future date is rejected.
    if status == 'Completed' && date.present? && date > Date.today && (new? || column_changed?(:status))
      errors.add(:status, "can't be Completed for a site visit scheduled in the future")
    end
  end

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
