class App::Models::Client < Sequel::Model
  include BCrypt

  # Self-referential: a client can be referred by another client
  # (referred_by_id, nullable — see migrations/0017_add_crm_fields_to_clients.rb).
  # `class: self` points the association back at this same model rather than
  # a real separate class named "ReferredBy". Note this is unrelated to the
  # separate `App::Models::Referral`/`referrals` table (the CRM Referrals
  # module, migrations/0016) — that's a different resource entirely; this is
  # purely a same-table self-join for "which client referred this one" /
  # "which clients did this one refer".
  many_to_one :referred_by, class: self
  one_to_many :referrals, key: :referred_by_id, class: self

  EMAIL_REGEXP = /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/

  # Defense-in-depth under the admin Clients form's / client-portal
  # register/update-profile forms' own client-side checks. `assigned_ram_id`/
  # `assigned_agent_slug` are plain nullable strings (no real FK, migrations/
  # 0017 — RAM/Agent Network precedent), so nothing at the DB level stops a
  # typo from silently creating an orphaned assignment; this adds a real
  # existence check. Scoped to `new? || column_changed?(...)` so an
  # unrelated edit to an already-existing client with a legacy bad
  # assignment doesn't suddenly start failing.
  def validate
    super
    validates_presence [:name, :email]
    validates_format(EMAIL_REGEXP, :email, message: 'is not a valid email address') if email.present?
    validates_unique(:email)
    errors.add(:phone, 'must be a 10-digit phone number') if phone.present? && phone.gsub(/\D/, '').length != 10
    if assigned_ram_id.present? && (new? || column_changed?(:assigned_ram_id)) && RamMember.where(slug: assigned_ram_id).first.nil?
      errors.add(:assigned_ram_id, 'must match an existing RAM team member')
    end
    if assigned_agent_slug.present? && (new? || column_changed?(:assigned_agent_slug)) && Agent.where(slug: assigned_agent_slug).first.nil?
      errors.add(:assigned_agent_slug, 'must match an existing agent')
    end
  end

  # Same bcrypt-over-encoded_password shape as User#password/RamMember#password
  # (models/user.rb, models/ram_member.rb) — kept as its own copy for the same
  # reason RamMember's is: separate portal, separate identity, separate JWT
  # (see helpers/current_client.rb).
  def password
    @password ||= Password.new(encoded_password)
  end

  def password=(new_password)
    @password = Password.create(new_password)
    self.encoded_password = @password
  end

  def generate_reset_token!
    self.reset_token = SecureRandom.urlsafe_base64
    self.reset_sent_at = Time.now
    save
  end

  def send_password_reset_email(base_url)
    generate_reset_token!

    client_email = self.email
    client_name = self.name
    reset_url = "#{base_url}/reset-password?token=#{CGI.escape(reset_token)}"

    mail = Mail.new do
      from    'apps@srinishtha.com'
      to      client_email
      subject 'Reset your REROCK Realty password'
      html_part do
        content_type 'text/html; charset=UTF-8'
        body <<-HTML
          <html>
          <body>
            <h1>Reset your password</h1>
            <p>Hello #{client_name},</p>
            <p>We received a request to reset your REROCK Realty client portal password. Click the link below to reset it:</p>
            <p><a href="#{reset_url}">Reset your password</a></p>
            <p>If you did not request a password reset, please ignore this email.</p>
            <p>Thank you,<br/>REROCK Realty</p>
          </body>
          </html>
        HTML
      end
    end

    mail.deliver!
  end

  # Admin-provisioned account's first password — same `mail` gem/SMTP infra
  # as send_password_reset_email/generate_and_send_otp! above. Sent instead
  # of showing the password in the admin UI (worse practice: browser
  # history/screen-share exposure for no benefit) since the client can
  # already self-service change it afterward via the portal's existing
  # Update Password flow.
  def send_temporary_password_email(temp_password)
    client_email = self.email
    client_name = self.name

    mail = Mail.new do
      from    'apps@srinishtha.com'
      to      client_email
      subject 'Your REROCK Realty client portal login'
      html_part do
        content_type 'text/html; charset=UTF-8'
        body <<-HTML
          <html>
          <body>
            <h1>Welcome to REROCK Realty</h1>
            <p>Hello #{client_name},</p>
            <p>An account has been created for you on the REROCK Realty client portal. Here is your temporary password:</p>
            <p style="font-size: 22px; font-weight: bold; letter-spacing: 2px;">#{temp_password}</p>
            <p>Please log in and change your password from your profile settings as soon as possible.</p>
            <p>Thank you,<br/>REROCK Realty</p>
          </body>
          </html>
        HTML
      end
    end

    mail.deliver!
  end

  # Real email-OTP verification, replacing the old verify-otp page's "any
  # complete 6-digit code succeeds" mock. No SMS gateway exists anywhere in
  # this codebase, so this is emailed (same `mail` gem/SMTP infra as password
  # reset above) rather than texted, despite the frontend copy still saying
  # "we sent a code to your email" either way — that copy was already
  # email-oriented (see PortalVerifyOtpForm's own `email` variable), so no
  # frontend text needed to change.
  def generate_and_send_otp!(base_url = nil)
    self.otp_code = format('%06d', SecureRandom.random_number(1_000_000))
    self.otp_sent_at = Time.now
    save

    client_email = self.email
    client_name = self.name
    code = self.otp_code

    mail = Mail.new do
      from    'apps@srinishtha.com'
      to      client_email
      subject 'Verify your REROCK Realty account'
      html_part do
        content_type 'text/html; charset=UTF-8'
        body <<-HTML
          <html>
          <body>
            <h1>Verify your email</h1>
            <p>Hello #{client_name},</p>
            <p>Your verification code is:</p>
            <p style="font-size: 28px; font-weight: bold; letter-spacing: 4px;">#{code}</p>
            <p>This code expires in 10 minutes. If you did not create a REROCK Realty account, please ignore this email.</p>
            <p>Thank you,<br/>REROCK Realty</p>
          </body>
          </html>
        HTML
      end
    end

    mail.deliver!
  end

  # Shaped to match the Client Portal's existing camelCase session fields
  # (ClientAuthContext.js's login(), and lib/data/clients.js/profile.js's
  # own mock shape every portal page was written against) — NOT the
  # snake_case `to_pos` dump the Admin Portal's real Clients resource
  # (services/clients.rb) settled on. Same "shape the response to match
  # what the existing frontend already expects" convention as
  # User#as_pos/RamMember#as_pos. Never includes encoded_password/
  # current_session_id/reset_token/otp_code.
  def as_pos
    {
      'id' => id,
      'name' => name,
      'email' => email,
      'phone' => phone,
      'avatar' => avatar,
      # "March 2022", not a raw ISO date — matches lib/data/profile.js's
      # currentUser.memberSince exactly (ClientSidebar/ClientTopbar display
      # it as free text, "Member since {memberSince}", with no date parsing
      # of their own).
      'memberSince' => joined&.strftime("%B %Y"),
      'location' => city,
      'status' => status,
      'type' => type,
      'assignedAgentSlug' => assigned_agent_slug,
      'assignedRamId' => assigned_ram_id,
      'referralCode' => referral_code,
      'referredById' => referred_by_id,
      'investedProperties' => invested_properties,
      'notes' => notes,
      'communicationLog' => communication_log,
      'timeline' => timeline,
      'emailVerified' => !email_verified_at.nil?,
      'createdAt' => created_at,
    }
  end
end
