class App::Models::Referral < Sequel::Model
  many_to_one :client
  many_to_one :property
  many_to_one :lead
  many_to_one :referral_link

  # Reverse side of Deal#referral_id / Commission#referral_id (both real FKs,
  # migrations/0060) — lets services/referrals.rb#list eager-load a RAM's
  # purchase/commission status per referral in two batched queries instead of
  # N+1.
  one_to_many :deals, key: :referral_id
  one_to_many :commissions, key: :referral_id

  # `agent_slug` has no DB-level FK (see migrations/0059's own comment —
  # deferred-string convention, same as Property/Lead/SiteVisit/Client),
  # so this adds a real existence check, same "typo shouldn't silently
  # create an orphaned assignment" reasoning as Client#validate's own
  # assigned_ram_id/assigned_agent_slug checks. Scoped to
  # `new? || column_changed?` so an unrelated edit to an already-existing
  # referral with a legacy bad value doesn't suddenly start failing.
  def validate
    super
    if agent_slug.present? && (new? || column_changed?(:agent_slug)) && App::Models::Agent.where(slug: agent_slug).first.nil?
      errors.add(:agent_slug, 'must match an existing agent')
    end
  end

  # Called after every status-changing save from both write paths
  # (RamPortal#update_my_referral and services/referrals.rb#update) — tells
  # the RAM the funnel moved, same "explicit call after save, guarded by an
  # actual-change check" convention as Deal#ensure_commission_for_closure!.
  # Only fires for the one terminal state a RAM would actually want to know
  # about unprompted; "Cancelled" is deliberately silent (per product
  # decision — a cancelled referral isn't a push-worthy event for the RAM),
  # and every earlier stage (Site Visit Scheduled, etc.) is something the
  # RAM already sees live on their own Referrals list.
  def notify_ram_of_status!
    return unless status == "Purchase Completed"
    return if ram_id.blank?

    ram = App::Models::RamMember.where(slug: ram_id).first
    return if ram.nil?

    App::Models::Notification.create(
      audience: 'ram',
      recipient_id: ram.id,
      type: 'referral',
      icon: 'PartyPopper',
      title: 'Referral purchased',
      message: "#{referred} completed their purchase — nice work!"
    )
  end
end
