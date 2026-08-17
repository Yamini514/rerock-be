class App::Models::Invoice < Sequel::Model
  many_to_one :deal
  many_to_one :client

  # This model had no validation at all before — `amount` could be saved
  # zero/negative, and `status` (documented in migrations/0023 as a plain
  # string with an "app-level allowed list" that was never actually
  # implemented anywhere) accepted any value. Same "must be one of"/
  # positive-amount convention as Community#total_units/Lead#status etc.
  STATUSES = ['Paid', 'Partially Paid', 'Unpaid'].freeze

  def validate
    super
    errors.add(:amount, 'must be greater than 0') if amount && amount <= 0
    errors.add(:status, "must be one of #{STATUSES.join(', ')}") if status.present? && !STATUSES.include?(status)
  end
end
