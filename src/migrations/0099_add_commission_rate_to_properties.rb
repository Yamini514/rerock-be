Sequel.migration do
  change do
    # Per-property override of the flat RAM commission rate — when set,
    # Deal#ensure_commission_for_closure! uses this instead of the
    # referring RAM's own `default_commission_rate` (models/ram_member.rb,
    # migrations/0061) for a deal on this specific property. Nullable: falls
    # back to the RAM's own rate, then Deal::DEFAULT_COMMISSION_RATE_PCT,
    # exactly like default_commission_rate's own fallback chain today.
    alter_table(:properties) do
      add_column :commission_rate, Float
    end
  end
end
