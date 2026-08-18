class App::Models::Commission < Sequel::Model
  many_to_one :referral
  many_to_one :deal
  many_to_one :ram_member

  # Same additive-FK-alongside-the-slug sync as models/lead.rb's own
  # sync_ram_reference! — see that file's comment.
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

  # Controlled lifecycle (CRM brief's own recommended states) — an admin can
  # move a commission forward or sideways into REJECTED/CANCELLED, but never
  # backward once APPROVED/PROCESSING/PAID, and never at all out of the three
  # terminal states. Enforced here (not just in the frontend) since
  # services/commissions.rb's #update is a plain whitelisted PUT otherwise —
  # this is the actual guard against "PAID back to PENDING" the brief warns
  # about. Uses the globally-enabled Sequel `:dirty` plugin (already relied
  # on by services/base.rb's audit-log hook) to see the pre-save value.
  ALLOWED_TRANSITIONS = {
    'NOT_ELIGIBLE' => %w[PENDING CANCELLED],
    'PENDING' => %w[ELIGIBLE UNDER_REVIEW NOT_ELIGIBLE REJECTED CANCELLED],
    'ELIGIBLE' => %w[UNDER_REVIEW APPROVED REJECTED CANCELLED],
    'UNDER_REVIEW' => %w[APPROVED REJECTED CANCELLED],
    'APPROVED' => %w[PROCESSING CANCELLED],
    'PROCESSING' => %w[PAID CANCELLED],
    'PAID' => [],
    'REJECTED' => [],
    'CANCELLED' => [],
  }.freeze

  def validate
    super
    if !new? && column_changed?(:status)
      from = initial_value(:status)
      allowed = ALLOWED_TRANSITIONS[from] || []
      unless allowed.include?(status)
        errors.add(:status, "cannot move from #{from} to #{status}")
      end
    end
  end

  # Called after every status-changing save (services/commissions.rb#update,
  # Deal#ensure_commission_for_closure!'s initial creation) — tells the RAM
  # about their commission, but deliberately only at the one moment that
  # matters to them ("a purchase you referred just earned you a commission"),
  # not every later admin-side lifecycle step (eligible/approved/processing/
  # paid/rejected/cancelled) — those stay visible to the RAM on their own
  # Income page, just without a push for each one, per product decision.
  def notify_ram_of_status!
    return unless status == 'PENDING'

    ram = App::Models::RamMember.where(slug: ram_id).first
    return if ram.nil?

    App::Models::Notification.create(
      audience: 'ram',
      recipient_id: ram.id,
      type: 'commission',
      icon: 'Wallet',
      title: 'Commission added',
      message: "A commission of #{format_inr(commission_amount)} was calculated for your referral."
    )
  end

  # Referral#payout_status ("whether the flat reward amount has actually
  # been paid out to the RAM" — migrations/0057) and this Commission's own
  # real, state-machine-governed `status` describe the same real-world
  # payout event from two different tables, with nothing keeping them in
  # sync — an admin marking a Commission PAID left the linked Referral's
  # payout_status stuck at its default 'Pending' forever, so the RAM
  # Portal/Admin Referrals list and the Commissions list could show
  # contradictory info for the same payout. Called after every
  # status-changing save (services/commissions.rb#update), same "explicit
  # call after save, guarded by an actual-change check" convention as
  # notify_ram_of_status! above. PAID is a terminal state (see
  # ALLOWED_TRANSITIONS — nothing can move away from it once reached), so
  # unlike Deal's property-status sync there's no reverse/reopen case to
  # handle here.
  def sync_referral_payout_status!
    return unless status == 'PAID'
    return if referral_id.nil?

    ref = referral
    return if ref.nil? || ref.payout_status == 'Paid'

    ref.update(payout_status: 'Paid')
  end

  private

  # Indian digit grouping (last 3 digits, then pairs) — matches the
  # frontend's own `formatINRFull` (lib/utils.js's `toLocaleString("en-IN")`)
  # so a notification's amount reads the same way as the UI it links back to.
  def format_inr(amount)
    digits = amount.to_i.abs.to_s
    if digits.length <= 3
      grouped = digits
    else
      last3 = digits[-3..]
      rest = digits[0..-4].reverse.scan(/\d{1,2}/).join(',').reverse
      grouped = "#{rest},#{last3}"
    end
    "₹#{grouped}"
  end
end
