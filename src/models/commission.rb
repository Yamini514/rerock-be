class App::Models::Commission < Sequel::Model
  many_to_one :referral
  many_to_one :deal

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
  # this commission belongs to about the change. Idempotent by construction:
  # only fires when `status` actually changed (or on the very first create),
  # matching the "only meaningful transitions" reasoning already used for
  # Base#write_audit_log!'s create-vs-update branch.
  def notify_ram_of_status!
    ram = App::Models::RamMember.where(slug: ram_id).first
    return if ram.nil?

    copy = {
      'PENDING' => ['Commission added', "A commission of #{format_inr(commission_amount)} was calculated for your referral."],
      'ELIGIBLE' => ['Commission eligible', "Your commission of #{format_inr(commission_amount)} is now eligible for payout."],
      'APPROVED' => ['Commission approved', "Your commission of #{format_inr(commission_amount)} has been approved."],
      'PROCESSING' => ['Commission processing', "Your commission of #{format_inr(commission_amount)} is being processed for payment."],
      'PAID' => ['Commission paid', "Your commission of #{format_inr(commission_amount)} has been paid out."],
      'REJECTED' => ['Commission rejected', "Your commission for this referral was rejected. Contact an admin for details."],
      'CANCELLED' => ['Commission cancelled', "Your commission for this referral was cancelled."],
    }[status]
    return if copy.nil?

    App::Models::Notification.create(
      audience: 'ram',
      recipient_id: ram.id,
      type: 'commission',
      icon: 'Wallet',
      title: copy[0],
      message: copy[1]
    )
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
