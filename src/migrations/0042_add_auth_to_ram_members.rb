Sequel.migration do
  change do
    # Additive alter_table — brings the RAM Portal's own self-service login
    # (previously 100% fake: RamAuthContext.js wrote a raw ram_members-shaped
    # record straight to localStorage after matching *any* password against
    # lib/data/staff.js's ramTeam mock) onto real bcrypt auth. Mirrors the
    # exact columns migrations/0004 + Users' own reset-token flow already use
    # for the same purpose on `users` — encoded_password + current_session_id
    # (the issued-JWT comparison target) + reset_token/reset_sent_at
    # (forgot/reset-password, services/users.rb's own pattern).
    alter_table(:ram_members) do
      add_column :encoded_password, String
      add_column :current_session_id, String
      add_column :reset_token, String
      add_column :reset_sent_at, DateTime
      add_column :last_logged_in_at, DateTime

      # Extended self-service profile fields (contact/professional/bank/KYC)
      # that only ever existed on the portal's own mock
      # (lib/data/ramProfileExtra.js), never on the Admin-facing ram_members
      # table. One jsonb blob, not individual columns — nothing anywhere
      # filters/sorts on these, same "whole object, no per-field
      # whitelisting" convention as Agent#documents / Client#notes.
      add_column :profile_extra, :jsonb, default: '{}'

      add_index :reset_token
    end
  end
end
