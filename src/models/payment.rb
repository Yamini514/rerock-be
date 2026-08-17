class App::Models::Payment < Sequel::Model
  many_to_one :deal
  many_to_one :client

  # This model had no validation at all before — `amount` could be saved
  # zero/negative, and `mode` (documented in migrations/0024 as a plain
  # string with an "app-level allowed list" that was never actually
  # implemented anywhere) accepted any value. `milestone` is deliberately
  # NOT validated against a fixed list (see migrations/0024's own comment —
  # a real payment ledger may need more milestones over time than the old
  # mock's two), so it's left alone here.
  MODES = ['Bank Transfer', 'UPI', 'Cheque', 'Net Banking'].freeze

  def validate
    super
    errors.add(:amount, 'must be greater than 0') if amount && amount <= 0
    errors.add(:mode, "must be one of #{MODES.join(', ')}") if mode.present? && !MODES.include?(mode)
  end
end
