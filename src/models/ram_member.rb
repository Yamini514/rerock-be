require 'uri'

class App::Models::RamMember < Sequel::Model
  include BCrypt

  # Same 10-digit Indian mobile shape Agent::PHONE_REGEXP already enforces
  # (backend/src/models/agent.rb) — RAM's own phone had no format check at
  # all before, only presence.
  PHONE_REGEXP = /\A[6-9]\d{9}\z/

  # Full Name/Email/Contact Number are the RAM record's mandatory core
  # fields. Contact number isn't a real column (phone lives in
  # profile_extra's jsonb, see #extract_phone), so its presence can't be
  # expressed via `validates_presence`. That check is scoped to
  # `new? || column_changed?(...)` rather than firing unconditionally on
  # every save — this is what lets a plain status-only PUT (Approve/
  # Activate/Deactivate, see services/ram_members.rb#update) keep working on
  # a legacy record that predates this rule without ever having to touch the
  # field it doesn't have; the moment someone actually edits that field, it
  # has to resolve to a non-blank value.
  #
  # `default_commission_rate` (migrations/0061) is deliberately NOT required
  # — commission rate is now set per-property instead (Property#
  # commission_rate, migrations/0099), which takes priority anyway (see
  # Deal#ensure_commission_for_closure!'s fallback chain); a RAM with no
  # default rate of their own just falls through to the flat
  # Deal::DEFAULT_COMMISSION_RATE_PCT.
  def validate
    super
    validates_presence [:name, :email]
    validates_unique(:email)
    errors.add(:email, "must be a valid email address") if email.present? && !email.match?(URI::MailTo::EMAIL_REGEXP)

    if new? || column_changed?(:profile_extra)
      errors.add(:phone, "Can't be blank") if extract_phone.blank?
      errors.add(:phone, "must be a valid 10-digit phone number") if extract_phone.present? && !extract_phone.match?(PHONE_REGEXP)
    end
    if new? || column_changed?(:profession)
      errors.add(:profession, "Can't be blank") if profession.blank?
    end
    if new? || column_changed?(:date_of_birth)
      errors.add(:date_of_birth, "Can't be blank") if date_of_birth.nil?
    end
    errors.add(:date_of_birth, "must result in an age between 18 and 49") if date_of_birth.present? && age && !age.between?(18, 49)
  end

  # Derived from date_of_birth, not a stored/directly-typed column (see
  # migrations/0087, mirroring Agent#age/migrations/0086) — this is what
  # #validate's "must result in an age between 18 and 49" check above reads, and what
  # #as_pos exposes as `age` to every existing caller unchanged. nil when
  # date_of_birth isn't set (a legacy record predating this rule).
  def age
    return nil if date_of_birth.nil?

    today = Date.today
    years = today.year - date_of_birth.year
    years -= 1 if today.month < date_of_birth.month || (today.month == date_of_birth.month && today.day < date_of_birth.day)
    years
  end

  def extract_phone
    # jsonb columns come back as Sequel::Postgres::JSONBHash/JSONHash, not a
    # plain Ruby Hash (`is_a?(Hash)` is false for both) — duck-type on `[]`
    # instead so this works whether profile_extra was just assigned a plain
    # Hash literal (pre-save) or round-tripped through the DB (post-save).
    return nil unless profile_extra.respond_to?(:[])
    profile_extra['phone'] || profile_extra[:phone]
  end

  # Same bcrypt-over-encoded_password shape as User#password/#password=
  # (models/user.rb) — kept as its own copy rather than a shared concern
  # since RamMember has no other relation to User (separate portal, separate
  # identity, separate JWT — see helpers/current_ram.rb).
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

    ram_email = self.email
    ram_name = self.name
    reset_url = "#{base_url}/reset-password?token=#{CGI.escape(reset_token)}"

    mail = Mail.new do
      from    'apps@srinishtha.com'
      to      ram_email
      subject 'Reset your RAM Portal password'
      html_part do
        content_type 'text/html; charset=UTF-8'
        body <<-HTML
          <html>
          <body>
            <h1>Reset your password</h1>
            <p>Hello #{ram_name},</p>
            <p>We received a request to reset your REROCK Advisory Member Portal password. Click the link below to reset it:</p>
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

  # Admin-provisioned account's first password (services/ram_members.rb's
  # new admin-invite path) — same `mail` gem/SMTP infra and "email it
  # instead of showing it in the admin UI" reasoning as
  # Client#send_temporary_password_email (models/client.rb). The RAM changes
  # it afterward via the portal's own existing self-service Update Password
  # flow (RamAuth#update_password), which also clears `must_change_password`.
  def send_temporary_password_email(temp_password)
    ram_email = self.email
    ram_name = self.name

    mail = Mail.new do
      from    'apps@srinishtha.com'
      to      ram_email
      subject 'Your REROCK Realty RAM Portal login'
      html_part do
        content_type 'text/html; charset=UTF-8'
        body <<-HTML
          <html>
          <body>
            <h1>Welcome to REROCK Realty</h1>
            <p>Hello #{ram_name},</p>
            <p>An account has been created for you on the REROCK Realty RAM Portal. Here is your temporary password:</p>
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

  # Shaped to match the RAM Portal's existing camelCase field names (the
  # mock it's replacing — lib/data/staff.js's ramTeam[] — predates this
  # build and every portal page/component was written against that exact
  # shape), NOT the snake_case `to_pos` dump the Admin Portal's own real
  # resources settled on. Same "shape the response to match what the
  # existing frontend already expects" convention as User#as_pos. Never
  # includes encoded_password/current_session_id/reset_token.
  def as_pos
    {
      'id' => id,
      'slug' => slug,
      'name' => name,
      'email' => email,
      'avatar' => avatar,
      'designation' => designation,
      'region' => region,
      'profession' => profession,
      'dateOfBirth' => date_of_birth,
      'age' => age,
      'dealsThisQuarter' => deals_this_quarter,
      'status' => status,
      'satisfaction' => satisfaction,
      'renewalRate' => renewal_rate,
      'avgResponseTimeHours' => avg_response_time_hours,
      'experienceYears' => experience_years,
      'revenueManaged' => revenue_managed,
      'conversionRatePct' => conversion_rate_pct,
      'referralGenerated' => referral_generated,
      'recommendations' => recommendations,
      'reports' => reports,
      'performance' => performance,
      'activities' => activities,
      'documents' => documents,
      'profileExtra' => profile_extra || {},
      'mustChangePassword' => must_change_password,
      'lastLoggedInAt' => last_logged_in_at,
      'createdAt' => created_at,
    }
  end
end
