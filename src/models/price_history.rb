class App::Models::PriceHistory < Sequel::Model
  many_to_one :community

  # `'manual'`/`'bulk'` rows (migrations/0056) are written exclusively by
  # services/communities.rb's `record_price_history!` as an immutable
  # side-effect of a real price change — never created/edited/deleted
  # directly. `'manual-entry'` (migrations/0078) is the one `change_type`
  # the new admin Price History CRUD (services/price_histories.rb) is
  # allowed to create/edit/delete, so backdated years (e.g. "2023") can be
  # entered by hand without touching the real audit trail.
  CHANGE_TYPES = ['manual', 'bulk', 'manual-entry'].freeze

  def validate
    super
    validates_presence [:community_id, :year], message: 'is required'
    if year && !year.between?(1990, Date.today.year + 1)
      errors.add(:year, "must be between 1990 and #{Date.today.year + 1}")
    end
    errors.add(:change_type, "must be one of #{CHANGE_TYPES.join(', ')}") if change_type.present? && !CHANGE_TYPES.include?(change_type)
  end
end
