class App::Models::Deal < Sequel::Model
  many_to_one :client
  many_to_one :property
  many_to_one :site_visit
  many_to_one :referral

  DEFAULT_COMMISSION_RATE_PCT = 1.0

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
