class App::Models::SiteVisit < Sequel::Model
  many_to_one :lead
  many_to_one :property
  many_to_one :community
  many_to_one :agent

  # Same additive-FK-alongside-the-slug sync as models/lead.rb's own
  # sync_agent_reference! — see that file's comment for the full reasoning.
  def before_validation
    if new?
      if agent_id.present?
        self.agent_slug = App::Models::Agent[agent_id]&.slug
      elsif agent_slug.present?
        self.agent_id = App::Models::Agent.where(slug: agent_slug).first&.id
      end
    elsif column_changed?(:agent_id)
      self.agent_slug = agent_id.present? ? App::Models::Agent[agent_id]&.slug : nil
    elsif column_changed?(:agent_slug)
      self.agent_id = agent_slug.present? ? App::Models::Agent.where(slug: agent_slug).first&.id : nil
    end
    super
  end

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

  # These three represent an appointment that hasn't happened yet — Completed
  # is exempt (it already happened, see the future-date check below) and so
  # is Cancelled (it just carries whatever date it was originally booked
  # for; cancelling one doesn't require picking a new date).
  FUTURE_REQUIRED_STATUSES = ['Pending', 'Scheduled', 'Rescheduled'].freeze

  def validate
    super
    errors.add(:status, "must be one of #{STATUSES.join(', ')}") if status.present? && !STATUSES.include?(status)

    # Completed is terminal — the visit already happened and, per
    # #ensure_deal_for_completion! below, may have already spawned a real
    # Deal off it. Nothing stopped an admin from then dragging it back to
    # Scheduled/Cancelled/Rescheduled afterward, which would misrepresent a
    # visit that already occurred and desyncs from that already-created
    # Deal. Scoped to an actual status change on an existing record (not
    # `new?` — a visit can't be created already-Completed-then-changed in
    # the same request) and only to the `status` field itself: notes/date/
    # time edits on an already-Completed visit stay allowed, same as
    # #ensure_deal_for_completion!'s own "re-saving a Completed visit to
    # edit notes must not create a second Deal" idempotency comment implies.
    if !new? && column_changed?(:status)
      old_status, = column_change(:status)
      errors.add(:status, "can't be changed — this site visit is already Completed") if old_status == 'Completed'
    end

    # An admin could reschedule a Pending/Scheduled/Rescheduled visit to a
    # date that's already passed — nothing rejected it. Scoped to the date
    # (or the status) actually changing so an unrelated notes-only edit on a
    # legacy row that predates this check never starts failing.
    if FUTURE_REQUIRED_STATUSES.include?(status) && date.present? && (new? || column_changed?(:date) || column_changed?(:status))
      errors.add(:date, "can't be in the past") if date < Date.today
    end

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

    # Same person, same exact moment, two different appointments — nothing
    # stopped that across any of the four booking surfaces (public site,
    # Client Portal, Agent Portal, admin), since each one only ever
    # validated its own record in isolation. Scoped by the underlying
    # Lead's client_phone (always present — Lead#validate requires it)
    # rather than lead_id: a fresh Lead is created on nearly every new
    # booking (client_site_visits.rb always makes a new one; the guest flow
    # in public_site_visits.rb only reuses an existing one if it's still
    # active), so two visits for the very same person routinely end up on
    # two different Lead rows — lead_id alone would miss most real
    # conflicts. Deliberately date+time together, not date alone: the same
    # person can easily have two visits on the same day at different
    # times, and that's not a conflict — only an identical time on an
    # identical date is something nobody can actually attend twice.
    # Cancelled visits don't count; they're not really "booked" anymore.
    if date.present? && time.present? && status != 'Cancelled' && (new? || column_changed?(:date) || column_changed?(:time) || column_changed?(:lead_id) || column_changed?(:status))
      phone = lead&.client_phone
      if phone.present?
        conflicting_lead_ids = App::Models::Lead.where(client_phone: phone).select(:id)
        conflict = self.class.where(lead_id: conflicting_lead_ids, date: date, time: time).exclude(status: 'Cancelled')
        conflict = conflict.exclude(id: id) unless new?
        errors.add(:date, 'already has another site visit booked at this exact date and time') if conflict.first
      end
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
      lead_id: lead_id,
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
