Sequel.migration do
  change do
    # Additive alter_table — same shape as 0042 (ram_members)/0043 (clients),
    # for the same reason: brings the Agent Portal's own self-service login
    # (previously 100% fake) onto real bcrypt auth.
    #
    # No `email_verified_at`/self-registration columns: unlike the Client
    # Portal, agents are provisioned by an admin (via the already-real
    # /admin/agents CRUD, services/agents.rb), never self-register — there is
    # deliberately no AgentAuth#register. An agent's *first* password is set
    # the same way a forgotten one is reset: the forgot-password flow below
    # doubles as account activation (see services/agent_auth.rb).
    #
    # otp_code/otp_sent_at ARE included, but mean something different here
    # than on `clients`: the existing AgentLoginPage/AgentVerifyOtpPage flow
    # already treats OTP as a **per-login 2FA step** (every sign-in redirects
    # to verify-otp, not just the first one), not a one-time email
    # verification — so these two columns get overwritten on every login
    # attempt rather than cleared-and-kept-nil after a single use.
    alter_table(:agents) do
      add_column :encoded_password, String
      add_column :current_session_id, String
      add_column :reset_token, String
      add_column :reset_sent_at, DateTime
      add_column :otp_code, String
      add_column :otp_sent_at, DateTime
      add_column :last_logged_in_at, DateTime

      add_index :reset_token
    end
  end
end
