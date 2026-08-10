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
end
