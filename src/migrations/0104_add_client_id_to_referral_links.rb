Sequel.migration do
  change do
    # A Client can now own a referral link too (general or property-
    # specific — same "own the row" pattern RAM already has), so `ram_id`
    # can no longer be `null: false`. A link belongs to exactly one of
    # ram_member_id/client_id, enforced in models/referral_link.rb#validate
    # rather than a DB constraint, matching this codebase's general
    # preference for Ruby-level validation over DB-level checks.
    alter_table(:referral_links) do
      set_column_allow_null :ram_id, true
      add_foreign_key :client_id, :clients
      add_index :client_id
    end
  end
end
