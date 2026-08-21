Sequel.migration do
  change do
    # Client-entered payout details (bank name, account number, IFSC, UPI ID)
    # so admin has somewhere real to look up how to pay a referral reward —
    # same jsonb-blob shape as RamMember#profile_extra's own `bank` sub-object
    # (models/ram_member.rb), just its own top-level column here since Client
    # has no equivalent `profile_extra` catch-all. Self-service only (see
    # services/client_auth.rb#update_profile) — admin can view it on the
    # Client Detail page but never edit it directly, same "the client is the
    # authority on their own payout details" reasoning as everywhere else a
    # field is self-service-only.
    alter_table(:clients) do
      add_column :bank_details, :jsonb, default: '{}'
    end
  end
end
