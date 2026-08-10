class App::Models::RamMember < Sequel::Model
  include BCrypt

  # No many_to_one/self-FK needed. `builder_ids` is a plain integer[] column
  # (like Agent#strong_area_ids / Property#tag_ids/#amenity_ids), not a Sequel
  # association — resolving it to full Builder records happens on the
  # frontend by filtering buildersApi's list against the id array (admin) or
  # the new public builders browse endpoint (RAM Portal — see routes.rb's
  # 'public' block, which reuses the existing Builders service as-is).

  def validate
    super
    validates_presence [:name, :email]
    validates_unique(:email)
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
      'buildersHandled' => builder_ids,
      'region' => region,
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
