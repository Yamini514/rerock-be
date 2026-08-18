class App::Models::Lead < Sequel::Model
  many_to_one :property
  many_to_one :community
  many_to_one :area
  many_to_one :client
  many_to_one :agent
  many_to_one :ram_member
  one_to_many :lead_status_histories

  # Keeps `agent_id`/`ram_member_id` (migrations/0088) in lockstep with the
  # deferred `agent_slug`/`ram_id` strings they were added alongside —
  # whichever of a pair was actually touched in this save wins and the
  # other is re-derived from it, so every existing `.where(agent_slug: ...)`/
  # `.where(ram_id: ...)` scoping query (agent_portal.rb/ram_portal.rb) never
  # has to change. `new?` can't rely on `column_changed?` (always false for
  # attributes set via `.new` — see #notify_agent_of_assignment!'s own
  # comment below), so a brand-new record instead just checks which of the
  # pair is actually present.
  def before_validation
    sync_agent_reference!
    sync_ram_reference!
    super
  end

  # A lead still open (not Closed/Lost) past this many days is auto-archived
  # by services/leads.rb#sweep_expired_leads! — see that method's own comment.
  VALIDITY_DAYS = 60

  # Statuses that end a lead's lifecycle — exempt from the 60-day
  # auto-archive sweep (services/leads.rb#sweep_expired_leads!) and from the
  # "does this phone already have an active lead" duplicate check below.
  # Lives on the model (not services/leads.rb, where it used to be a
  # service-local constant) so both call sites share one definition.
  TERMINAL_STATUSES = ['Closed', 'Lost'].freeze

  # The real funnel order (see services/ram_portal.rb's own "Enquiry ->
  # Qualified Lead -> Site Visit -> Negotiation -> Agreement -> Closed"
  # comment, matching lib/data/leads.js's LEAD_STATUSES). `Lost` is
  # deliberately excluded — it's a terminal exit from the funnel, not a step
  # within it, so moving to Lost is never treated as "backward" by the
  # check below.
  STAGE_ORDER = ['Enquiry', 'Qualified Lead', 'Site Visit', 'Negotiation', 'Agreement', 'Closed'].freeze

  # Ordered, real audit trail of every status change — written server-side,
  # insert-only (services/leads.rb#create/#update, services/agent_portal.rb#
  # update_my_lead), never trusting a client-supplied history row. Distinct
  # from #timeline below, which stays freeform/client-supplied.
  def status_history
    lead_status_histories_dataset.order(:created_at).all.map(&:to_pos)
  end

  # Read shape used everywhere a Lead is returned (services/leads.rb,
  # services/agent_portal.rb) — same "merge computed data into to_pos"
  # convention as FollowUp#with_overdue/Agent#with_live_stats.
  def with_status_history
    to_pos.merge('status_history' => status_history)
  end

  # Item 16 of the spec: a lead is only ever "active" while it's non-terminal
  # and within its own 60-day validity window (same window
  # sweep_expired_leads! auto-archives past) — an expired or Closed/Lost
  # lead for the same phone number doesn't block a fresh enquiry. Used by
  # services/leads.rb#create and services/ram_portal.rb#create_my_lead, the
  # two real lead-creation entry points.
  def self.duplicate_active?(phone)
    return false if phone.blank?

    cutoff = Time.now - (VALIDITY_DAYS * 24 * 60 * 60)
    where(client_phone: phone, archived: false).exclude(status: TERMINAL_STATUSES).where { created_at > cutoff }.first ? true : false
  end

  # Called after every save from services/leads.rb — #create calls this
  # unconditionally (a lead entered with an agent already picked is always
  # a fresh assignment), #update calls it only when the caller has already
  # determined `agent_slug` actually changed (computed *before* the save,
  # same "compare the incoming value to the pre-save value" convention as
  # Commissions#update's own `status_changing` — deliberately NOT
  # `column_changed?`, since that only reflects changes made after a
  # record is loaded and is always false for values set via `.new` at
  # creation, which would silently break the #create call site).
  def notify_agent_of_assignment!
    return if agent_slug.blank?

    agent = App::Models::Agent.where(slug: agent_slug).first
    return if agent.nil?

    App::Models::Notification.create(
      audience: 'agent',
      recipient_id: agent.id,
      type: 'lead',
      icon: 'UserPlus',
      title: 'New lead assigned',
      message: "A new lead has been assigned to you: #{client_name}."
    )
  end

  EMAIL_REGEXP = /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/

  # Defense-in-depth under the admin "Log Enquiry" form's / public contact
  # form's / client-portal enquiry form's own client-side checks — a direct
  # API call bypasses those entirely today. `client_email` stays optional
  # (a walk-in lead may only have a phone number) but is format-checked
  # when present; note the Won->Client auto-conversion flow
  # (services/leads.rb#update) has its own, stricter "email required to
  # convert" gate — that's a business-flow rule, not a data-shape one, so it
  # lives in the service, not here. The RAM Portal's "New Client" lead
  # capture (services/ram_portal.rb#create_my_lead) additionally requires
  # email at the service level — every creation path still always collects
  # a real phone number, so `client_phone` stays a hard presence requirement
  # here (it's also a NOT NULL column — migrations/0014).
  def validate
    super
    validates_presence [:client_name, :client_phone]
    validates_format(EMAIL_REGEXP, :client_email, message: 'is not a valid email address') if client_email.present?
    errors.add(:client_phone, 'must be a 10-digit phone number') if client_phone.present? && client_phone.gsub(/\D/, '').length != 10

    # A completed SiteVisit is a real, already-happened milestone — nothing
    # stopped the lead's own status from being dragged back to Enquiry/
    # Qualified Lead afterward, which would misrepresent the funnel (and
    # under-report site-visit-stage-or-later counts on the Reports/Enquiries
    # pages). Scoped to an actual status change on an existing lead — a
    # brand-new lead can't yet have any site visits tied to its own id.
    if !new? && column_changed?(:status) && STAGE_ORDER.include?(status) && STAGE_ORDER.index(status) < STAGE_ORDER.index('Site Visit')
      if App::Models::SiteVisit.where(lead_id: id, status: 'Completed').first
        errors.add(:status, "can't move back to #{status} — a site visit for this lead has already been completed")
      end
    end
  end

  private

  def sync_agent_reference!
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
  end

  def sync_ram_reference!
    if new?
      if ram_member_id.present?
        self.ram_id = App::Models::RamMember[ram_member_id]&.slug
      elsif ram_id.present?
        self.ram_member_id = App::Models::RamMember.where(slug: ram_id).first&.id
      end
    elsif column_changed?(:ram_member_id)
      self.ram_id = ram_member_id.present? ? App::Models::RamMember[ram_member_id]&.slug : nil
    elsif column_changed?(:ram_id)
      self.ram_member_id = ram_id.present? ? App::Models::RamMember.where(slug: ram_id).first&.id : nil
    end
  end
end
