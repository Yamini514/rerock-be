Sequel.migration do
  change do
    # Admin-configured default commission rate (%) applied to this RAM's
    # future closed deals (Deal#ensure_commission_for_closure!) when set —
    # replaces the old free-entry "Performance Metrics" fields as the one
    # thing an admin actually needs to configure per RAM. Nullable: falls
    # back to Deal::DEFAULT_COMMISSION_RATE_PCT when not set.
    alter_table(:ram_members) do
      add_column :default_commission_rate, Float
    end
  end
end
