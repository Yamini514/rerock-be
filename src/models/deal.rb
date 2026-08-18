class App::Models::Deal < Sequel::Model
  many_to_one :client
  many_to_one :property
  many_to_one :site_visit
  many_to_one :referral
  many_to_one :agent
  many_to_one :lead
  one_to_many :deal_status_histories

  DEFAULT_COMMISSION_RATE_PCT = 1.0

  # Same additive-FK-alongside-the-slug sync as models/lead.rb's own
  # sync_agent_reference! — see that file's comment. No sync needed for
  # `lead_id` (migrations/0091): it's a plain new FK, not paired with any
  # deferred string.
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

  # "Did this Deal originate from a RAM Referral?" — no direct column,
  # transitively resolved through the real referral_id FK (migrations/0060)
  # rather than a redundant ram_member_id copied onto Deal itself.
  def ram_member
    referral&.ram_member
  end

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

  # Closing a Deal moves real inventory, but the linked Property's own
  # `status` (Available/Reserved/Sold/...) was otherwise left for an admin
  # to remember to flip by hand every single time — which the public site
  # and Agent/RAM portals all read as gospel (Properties#list never
  # excludes Sold from browsing/recommending) and which the Inventory
  # report (services/reports.rb#inventory) counts live off this same
  # column, so a forgotten manual flip silently corrupts both. Same "call
  # unconditionally after save, guard by an actual stage change" convention
  # as ensure_commission_for_closure!/notify_client_of_closure! below.
  # Reopening a deal (moving it off Closed) reverts the property back to
  # Available, but only if it's still exactly 'Sold' — i.e. still whatever
  # this method itself set. An admin's own manual override to something
  # else (e.g. Reserved for a different buyer in the meantime) is never
  # clobbered by a reopened deal.
  def sync_property_status_for_stage!
    return unless column_changed?(:stage)
    return if property_id.nil?

    prop = property
    return if prop.nil?

    old_stage, new_stage = column_change(:stage)

    if new_stage == 'Closed'
      prop.update(status: 'Sold') unless prop.status == 'Sold'
    elsif old_stage == 'Closed'
      prop.update(status: 'Available') if prop.status == 'Sold'
    end
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
