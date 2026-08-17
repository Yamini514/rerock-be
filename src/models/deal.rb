class App::Models::Deal < Sequel::Model
  many_to_one :client
  many_to_one :property
  many_to_one :site_visit
  many_to_one :referral
  one_to_many :deal_status_histories

  DEFAULT_COMMISSION_RATE_PCT = 1.0

  # Ordered, real audit trail of every stage change — written server-side,
  # insert-only (services/deals.rb#create/#update, services/agent_portal.rb#
  # update_my_deal), never trusting a client-supplied history row. Same
  # shape/reasoning as Lead#status_history/Client#status_history, keyed on
  # this table's `stage` column rather than a `status` column. Distinct from
  # #notes, which stays freeform/client-supplied.
  def status_history
    deal_status_histories_dataset.order(:created_at).all.map(&:to_pos)
  end

  # Read shape used everywhere a Deal is returned (services/deals.rb,
  # services/agent_portal.rb) — same "merge computed data into to_pos"
  # convention as Lead#with_status_history.
  def with_status_history
    to_pos.merge('status_history' => status_history)
  end

  # Called after every save from both the admin (services/deals.rb#update)
  # and agent-portal (services/agent_portal.rb#update_my_deal) update paths
  # — same "call unconditionally after save, guard with an idempotent check"
  # convention as SiteVisit#ensure_deal_for_completion!. Fires the
  # "Commission Calculation" step of the RAM referral flow the moment a
  # deal tied to a real Referral reaches Closed: computed math only (sale
  # value × a flat rate), landing as PENDING — every subsequent lifecycle
  # step (eligible/approved/processing/paid/rejected) stays an explicit
  # admin decision via services/commissions.rb, never automatic.
  def ensure_commission_for_closure!
    return unless stage == 'Closed'
    return if referral_id.nil?
    return if App::Models::Commission.where(deal_id: id).first

    ref = referral
    return if ref.nil? || ref.ram_id.blank?

    ram = App::Models::RamMember.where(slug: ref.ram_id).first
    rate = ram&.default_commission_rate.presence || DEFAULT_COMMISSION_RATE_PCT
    amount = (value.to_i * rate / 100.0).round

    commission = App::Models::Commission.create(
      referral_id: ref.id,
      deal_id: id,
      ram_id: ref.ram_id,
      sale_amount: value.to_i,
      commission_rate: rate,
      commission_amount: amount,
      status: 'PENDING'
    )
    commission.notify_ram_of_status!
  end

  # Agent Network's per-agent analogue of the RAM commission hook above —
  # same "call unconditionally after save, guard idempotently" convention
  # (services/deals.rb#update), but stamps the rate/amount directly onto
  # this deal (migrations/0075) instead of creating a row in a separate
  # table, since there's no per-agent commission workflow to track, just the
  # one rate/amount used at closure. `agent_commission_amount.present?`
  # guards against ever overwriting an already-stamped deal — that's what
  # makes a later change to the agent's own `commission_rate` not rewrite
  # this deal's historical commission (see Agent#live_stats, which reads
  # this stamped value instead of recomputing from the agent's current
  # rate). Deliberately not also wired into Deals#create — same scope as
  # `ensure_commission_for_closure!` above, which only fires from #update.
  def ensure_agent_commission_for_closure!
    return unless stage == 'Closed'
    return if agent_slug.blank?
    return if agent_commission_amount.present?

    agent = App::Models::Agent.where(slug: agent_slug).first
    return if agent.nil?

    rate = agent.commission_rate.to_f
    self.agent_commission_rate = rate
    self.agent_commission_amount = (value.to_i * rate / 100.0).round
    save_changes(validate: false)
  end

  # Called after every save from both the admin (services/deals.rb#update)
  # and agent-portal (services/agent_portal.rb#update_my_deal) update paths
  # — same "call unconditionally after save, guard with an actual-change
  # check" convention as SiteVisit#notify_client_of_status!. Fires once, the
  # moment a deal reaches Closed, telling the client whose purchase it is.
  # No-op for a deal with no linked client account (e.g. one entered with
  # just a free-typed client_name, per Deals#create's own comment).
  def notify_client_of_closure!
    return unless column_changed?(:stage)
    return unless stage == 'Closed'
    return if client_id.nil?

    App::Models::Notification.create(
      audience: 'client',
      recipient_id: client_id,
      type: 'deal',
      icon: 'PartyPopper',
      title: 'Deal closed',
      message: "Congratulations! Your purchase#{property_name.present? ? " of #{property_name}" : ""} has been finalized."
    )
  end
end
