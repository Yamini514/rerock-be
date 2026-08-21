Sequel.migration do
  change do
    # `referrals.client_id` already means "the referred person, once
    # matched/created as a real Client" (see models/referral.rb's own
    # comment) — a Client acting as the REFERRER needs its own column.
    # Nullable: most referrals still have no client referrer (RAM/Agent/
    # admin-manual rows).
    alter_table(:referrals) do
      add_foreign_key :referrer_client_id, :clients
      add_index :referrer_client_id
    end

    # A referrer_client_id referral now gets the same real, rate x sale,
    # lifecycle-tracked Commission row RAM referrals already get
    # (Deal#ensure_commission_for_closure!), instead of the flat admin-typed
    # `reward` field being the only payout signal. `ram_id` drops its NOT
    # NULL so a client-driven commission (no RAM involved at all) can leave
    # it blank; exactly one of ram_id/client_id is ever set per row.
    alter_table(:commissions) do
      add_foreign_key :client_id, :clients
      add_index :client_id
      set_column_allow_null :ram_id, true
    end

    # Admin-configured default commission rate (%) applied to this client's
    # future closed deals when they're the referrer — same optional,
    # falls-back-to-the-property-rate-then-the-flat-default role as
    # RamMember#default_commission_rate (migrations/0061).
    alter_table(:clients) do
      add_column :commission_rate, Float
    end
  end
end
