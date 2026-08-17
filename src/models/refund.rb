class App::Models::Refund < Sequel::Model
  many_to_one :client
  many_to_one :property

  # This model had no validation at all before — `amount` could be saved
  # zero/negative, and `status` (documented in migrations/0025 as a plain
  # string with an "app-level allowed list" that was never actually
  # implemented anywhere) accepted any value. Same convention as
  # Invoice#status/STATUSES.
  STATUSES = ['Requested', 'Processed', 'Rejected'].freeze

  def validate
    super
    errors.add(:amount, 'must be greater than 0') if amount && amount <= 0
    errors.add(:status, "must be one of #{STATUSES.join(', ')}") if status.present? && !STATUSES.include?(status)
  end
end
