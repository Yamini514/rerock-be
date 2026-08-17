class App::Models::Lead < Sequel::Model
  many_to_one :property
  many_to_one :community
  many_to_one :area
  many_to_one :client
  one_to_many :lead_status_histories

  # A lead still open (not Closed/Lost) past this many days is auto-archived
  # by services/leads.rb#sweep_expired_leads! — see that method's own comment.
  VALIDITY_DAYS = 60

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
  end
end
