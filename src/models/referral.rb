class App::Models::Referral < Sequel::Model
  many_to_one :client
  many_to_one :property
  many_to_one :community
  many_to_one :lead
  many_to_one :referral_link
  many_to_one :ram_member

  # Reverse side of Deal#referral_id / Commission#referral_id (both real FKs,
  # migrations/0060) — lets services/referrals.rb#list eager-load a RAM's
  # purchase/commission status per referral in two batched queries instead of
  # N+1.
  one_to_many :deals, key: :referral_id
  one_to_many :commissions, key: :referral_id

  # Same additive-FK-alongside-the-slug sync as models/lead.rb's own
  # sync_ram_reference! — see that file's comment. `agent_slug` deliberately
  # has no matching `agent_id` (see migrations/0092's own comment).
  def before_validation
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
    super
  end

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

    # `reward` is a flat, admin-entered amount with no state machine of its
    # own (unlike Commission's real ALLOWED_TRANSITIONS) — nothing stopped
    # it from being recorded while the referral was still sitting at
    # Enquiry Stage/Site Visit Scheduled, before there was actually a sale
    # to reward. Purchase Completed is the one stage that already means
    # "the sale happened" (see notify_ram_of_status!'s own gate on this
    # exact string), so that's the natural point a reward becomes valid.
    # Scoped to `new? || column_changed?(:reward/:status)` so an unrelated
    # edit to an already-existing referral with a legacy bad value doesn't
    # suddenly start failing — same convention as the agent_slug check
    # above. Moving a Purchase Completed referral's status back down (a
    # correction/cancellation) is still allowed, but only once the reward
    # is cleared too, since a nonzero reward on a non-completed referral is
    # exactly the inconsistent state this guards against either way.
    if reward.to_i != 0 && status != 'Purchase Completed' && (new? || column_changed?(:reward) || column_changed?(:status))
      errors.add(:reward, 'can only be set once the referral reaches Purchase Completed')
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
