Sequel.migration do
  change do
    # Additive alter_table — same purpose and shape as migrations/0042's
    # ram_members equivalent: brings the Client Portal's own self-service
    # login (previously 100% fake: ClientAuthContext.js wrote a raw
    # {name,email,phone,avatar,...} session straight to localStorage after
    # matching *any* password against a single hardcoded demo client) onto
    # real bcrypt auth. encoded_password/current_session_id/reset_token/
    # reset_sent_at mirror migrations/0004 (users) and 0042 (ram_members)
    # exactly.
    #
    # Two columns beyond the ram_members precedent, specific to this portal:
    #   - otp_code/otp_sent_at — the existing RamRegisterPage/PortalLoginPage
    #     UX includes a "verify your email" OTP step (frontend/app/portal/
    #     verify-otp/page.js) that was previously 100% fake ("any complete
    #     6-digit code verifies successfully"). Real SMS delivery is out of
    #     scope (no SMS gateway integration exists anywhere in this
    #     codebase), but real *email* delivery already works (Client/RamMember
    #     #send_password_reset_email both use the `mail` gem over real SMTP)
    #     — so this reuses that same infrastructure for a real emailed code
    #     instead of a fabricated always-succeeds step.
    #   - referral_code — a client's own shareable invite code (looked up at
    #     registration time to resolve `referred_by_id`, migrations/0017).
    #     No equivalent existed on ram_members; RAM Portal registration has
    #     no referral concept.
    alter_table(:clients) do
      add_column :encoded_password, String
      add_column :current_session_id, String
      add_column :reset_token, String
      add_column :reset_sent_at, DateTime
      add_column :last_logged_in_at, DateTime

      add_column :otp_code, String
      add_column :otp_sent_at, DateTime
      add_column :email_verified_at, DateTime

      add_column :referral_code, String

      add_index :reset_token
      add_index :referral_code, unique: true
    end
  end
end
