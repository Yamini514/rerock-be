Sequel.migration do
  # `price_histories` (migrations/0056) had no `year` column — rows were only
  # ever grouped by `effective_date`. Admin-managed "Pricing History" entries
  # (year + starting + ending price, entered by hand for years that predate
  # this system) need a clean, explicit year to key off rather than deriving
  # one from a timestamp every time. Backfilled from the existing
  # `effective_date` for rows already written by the auto-logging path
  # (services/communities.rb's `record_price_history!`) so charting-by-year
  # works for historical data without a gap.
  up do
    alter_table(:price_histories) { add_column :year, Integer }

    from(:price_histories).where(year: nil).update(
      year: Sequel.function(:extract, :year, :effective_date).cast(:integer)
    )

    alter_table(:price_histories) { add_index [:community_id, :year] }
  end

  down do
    alter_table(:price_histories) do
      drop_index [:community_id, :year]
      drop_column :year
    end
  end
end
