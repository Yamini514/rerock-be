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

  # Closing a Deal with no real sale value (left at the form's own default
  # of 0) used to sail through silently — and since
  # #sync_client_investment! below copies this value verbatim into
  # Client#invested_properties, it produced a real, visible "Total
  # Invested: ₹0" on that client's own Dashboard/Portfolio despite them
  # genuinely owning a property. Scoped to new?/stage actually changing so
  # an unrelated edit (e.g. notes) on a legacy deal that closed before this
  # check existed doesn't suddenly start failing.
  def validate
    super
    if stage == 'Closed' && (new? || column_changed?(:stage)) && value.to_i <= 0
      errors.add(:value, "must be greater than 0 before this deal can be closed")
    end
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

  # Called after every save from the admin's own create AND update
  # (services/deals.rb#create/#update) and the agent-portal's update path
  # (services/agent_portal.rb#update_my_deal) — same "call unconditionally
  # after save, guard with an idempotent check" convention as
  # SiteVisit#ensure_deal_for_completion!. Fires the "Commission
  # Calculation" step of the RAM referral flow the moment a deal tied to a
  # real Referral reaches Closed (whether it reached Closed via a later
  # stage move, or was created already Closed): computed math only (sale
  # value × a rate), landing as PENDING — every subsequent lifecycle step
  # (eligible/approved/processing/paid/rejected) stays an explicit admin
  # decision via services/commissions.rb, never automatic.
  #
  # Rate priority: the specific Property's own `commission_rate`
  # (migrations/0099) first — it's the more specific override when an
  # admin has set one — then the referring RAM's own `default_commission_
  # rate` (migrations/0061), then the flat DEFAULT_COMMISSION_RATE_PCT.
  def ensure_commission_for_closure!
    return unless stage == 'Closed'
    return if referral_id.nil?
    return if App::Models::Commission.where(deal_id: id).first

    ref = referral
    return if ref.nil? || ref.ram_id.blank?

    ram = App::Models::RamMember.where(slug: ref.ram_id).first
    rate = property&.commission_rate.presence || ram&.default_commission_rate.presence || DEFAULT_COMMISSION_RATE_PCT
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
  # (services/deals.rb#create/#update), but stamps the rate/amount directly onto
  # this deal (migrations/0075) instead of creating a row in a separate
  # table, since there's no per-agent commission workflow to track, just the
  # one rate/amount used at closure. `agent_commission_amount.present?`
  # guards against ever overwriting an already-stamped deal — that's what
  # makes a later change to the agent's own `commission_rate` not rewrite
  # this deal's historical commission (see Agent#live_stats, which reads
  # this stamped value instead of recomputing from the agent's current
  # rate). Wired into both Deals#create and #update, same as
  # `ensure_commission_for_closure!` above.
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

  # Called after every save from the admin's own create AND update
  # (services/deals.rb#create/#update) and the agent-portal's update path
  # (services/agent_portal.rb#update_my_deal) — same "call unconditionally
  # after save, guard with an actual-change check" convention as
  # SiteVisit#notify_client_of_status!. Fires once, the moment a deal
  # reaches Closed (whether via a later stage move or created already
  # Closed), telling the client whose purchase it is. No-op for a deal with
  # no linked client account (e.g. one entered with just a free-typed
  # client_name, per Deals#create's own comment).
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

  # Closing a Deal is also the moment it becomes a real purchase on the
  # client's own record — nothing wired this up before. Client#invested_properties
  # (what the Client Portal's own Portfolio page reads — app/portal/(dashboard)/
  # portfolio/PortfolioClient.js) was only ever set by hand, once, when an
  # admin created the Client row in the first place (ClientForm.js's own
  # one-time seed on create) — closing a deal for an existing client never
  # touched it, so a real, closed sale silently never showed up in that
  # client's own Portfolio. Called unconditionally after every save
  # (services/deals.rb#create/#update), same "explicit call after save"
  # convention as ensure_commission_for_closure! above — but unlike that
  # method's own "skip if a row already exists" guard, this one *replaces*
  # an existing entry for the same property rather than skipping outright:
  # an earlier version of this method only ever skipped, which meant fixing
  # a deal that had first closed with an incorrect/zero `value` (now
  # rejected up front by this model's own `validate`, but already-existing
  # rows predate that) could never actually correct the client's Portfolio
  # — the stale entry just sat there forever. Deliberately does NOT try to
  # *remove* the entry if the deal is later reopened (moved off Closed) —
  # unlike #sync_property_status_for_stage!'s property-status revert,
  # there's no deal_id stored per invested_properties entry to safely tell
  # "this is the one I added" apart from one an admin added by hand, so
  # removing here risks deleting real data instead of just undoing this
  # method's own work.
  def sync_client_investment!
    return unless stage == 'Closed'
    return if client_id.nil? || property_id.nil?

    client = self.client
    return if client.nil?

    existing = client.invested_properties || []
    prop = property
    entry = {
      'propertyId' => property_id,
      'slug' => prop&.slug,
      'purchasePrice' => value.to_i,
      'currentValue' => value.to_i,
      'purchaseDate' => (closing_date || Date.today).to_s
    }

    index = existing.find_index { |h| (h['propertyId'] || h[:propertyId]).to_i == property_id }
    updated = index ? existing.each_with_index.map { |h, i| i == index ? entry : h } : existing + [entry]
    return if updated == existing

    client.invested_properties = updated
    client.save_changes(validate: false)
  rescue => e
    # Same "must never fail the real operation that already succeeded"
    # contract as Base#write_audit_log!/Communities#record_price_history! —
    # a broken write here must not surface as a failure of the deal closure
    # itself.
    App.logger.error("[Deal] sync_client_investment! failed for Deal ##{id}: #{e.message}")
    App.logger.error(e.backtrace)
  end

  # Closing a Deal is also the moment its originating enquiry is actually
  # done — nothing wired this up before, so the admin Enquiries table could
  # show a Lead sitting at "New"/"Qualified Lead"/etc. forever even after the
  # real Deal born from it had already closed. `lead_id` is a real FK
  # (migrations/0091, `Deal#lead`), and Lead's own status enum already has a
  # matching terminal 'Closed' value (models/lead.rb's STAGE_ORDER/
  # TERMINAL_STATUSES), so this just carries the same status string across
  # rather than inventing a new one. Idempotent via "already Closed" rather
  # than a `column_changed?(:stage)` gate — deliberately, since that check is
  # unreliable for a deal *created* already at stage: 'Closed' (see this
  # model's own before_validation comment on column_changed? and `.new`), and
  # this needs to fire for that case too, same reasoning as
  # ensure_commission_for_closure!/sync_client_investment! above using their
  # own idempotency check instead of column_changed?.
  #
  # One-way on purpose: if the Deal is later reopened (moved off Closed),
  # this never reverts the Lead back — Lead#validate's own terminal-status
  # guard already hard-blocks un-closing a Lead by design (same one-way
  # reasoning as a completed SiteVisit's own guard), so a revert attempt here
  # would just fail validation silently. Reopening a deal for correction
  # doesn't mean the enquiry that produced it stopped being a real, closed
  # enquiry.
  def sync_lead_status_for_closure!
    return unless stage == 'Closed'
    return if lead_id.nil?

    l = lead
    return if l.nil? || l.status == 'Closed'

    l.status = 'Closed'
    l.save
  rescue => e
    App.logger.error("[Deal] sync_lead_status_for_closure! failed for Deal ##{id}: #{e.message}")
    App.logger.error(e.backtrace)
  end
end
