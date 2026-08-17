class App::Models::Review < Sequel::Model
  many_to_one :client

  # This model had no validation at all before — `status` (default
  # 'Pending', migrations/0046) accepted any value. That's more than a
  # generic data-integrity gap here: services/public_reviews.rb's public
  # list does an EXACT match on `status: 'Approved'`, so a typo'd status
  # (e.g. "aproved") saved via the admin moderation UI would silently
  # remove that review from the public site forever, with no error raised
  # anywhere to explain why. Same "must be one of" convention as
  # SiteVisit#status/Invoice#status.
  STATUSES = ['Pending', 'Approved', 'Rejected'].freeze

  def validate
    super
    errors.add(:status, "must be one of #{STATUSES.join(', ')}") if status.present? && !STATUSES.include?(status)
  end
end
