class App::Models::Agent < Sequel::Model
  include BCrypt

  # No many_to_one/self-FK needed. `strong_area_ids` is a plain integer[]
  # column (like Property#tag_ids/#amenity_ids), not a Sequel association —
  # resolving it to full Area records happens on the frontend by filtering
  # areasApi's list against the id array (admin) or the public areas browse
  # endpoint (Agent Portal — routes.rb's 'public' block).

  # Same bcrypt-over-encoded_password shape as User/RamMember/Client — see
  # helpers/current_agent.rb for why this is its own copy, not a shared
  # concern.
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

  # Doubles as "activate my account" for an agent who has never set a
  # password at all (encoded_password nil — the normal state right after an
  # admin creates the record via /admin/agents) — see services/agent_auth.rb#login's
  # comment on why there is no separate AgentAuth#register.
  def send_password_reset_email(base_url)
    generate_reset_token!

    agent_email = self.email
    agent_name = self.name
    reset_url = "#{base_url}/reset-password?token=#{CGI.escape(reset_token)}"

    mail = Mail.new do
      from    'apps@srinishtha.com'
      to      agent_email
      subject 'Set/reset your REROCK Realty agent password'
      html_part do
        content_type 'text/html; charset=UTF-8'
        body <<-HTML
          <html>
          <body>
            <h1>Set your password</h1>
            <p>Hello #{agent_name},</p>
            <p>Click the link below to set or reset your REROCK Realty agent portal password:</p>
            <p><a href="#{reset_url}">Set your password</a></p>
            <p>If you did not request this, please ignore this email.</p>
            <p>Thank you,<br/>REROCK Realty</p>
          </body>
          </html>
        HTML
      end
    end

    mail.deliver!
  end

  # Per-login 2FA code (not a one-time email-verification code like
  # Client#generate_and_send_otp! — see migrations/0044's comment). Sent
  # fresh on every successful password check in services/agent_auth.rb#login.
  def generate_and_send_otp!
    self.otp_code = format('%06d', SecureRandom.random_number(1_000_000))
    self.otp_sent_at = Time.now
    save

    agent_email = self.email
    agent_name = self.name
    code = self.otp_code

    mail = Mail.new do
      from    'apps@srinishtha.com'
      to      agent_email
      subject 'Your REROCK Realty sign-in code'
      html_part do
        content_type 'text/html; charset=UTF-8'
        body <<-HTML
          <html>
          <body>
            <h1>Your sign-in code</h1>
            <p>Hello #{agent_name},</p>
            <p>Your verification code is:</p>
            <p style="font-size: 28px; font-weight: bold; letter-spacing: 4px;">#{code}</p>
            <p>This code expires in 10 minutes. If you did not attempt to sign in, please ignore this email.</p>
            <p>Thank you,<br/>REROCK Realty</p>
          </body>
          </html>
        HTML
      end
    end

    mail.deliver!
  end

  # Shaped to match the Agent Portal's existing camelCase mock shape
  # (lib/data/agents.js) every portal page/component was written against —
  # same "shape the response to match what the existing frontend already
  # expects" convention as User#as_pos/RamMember#as_pos/Client#as_pos. Never
  # includes encoded_password/current_session_id/reset_token/otp_code.
  def as_pos
    {
      'id' => id,
      'slug' => slug,
      'name' => name,
      'role' => role,
      'email' => email,
      'phone' => phone,
      'whatsapp' => whatsapp,
      'avatar' => avatar,
      'specialization' => specialization,
      'dealsClosed' => deals_closed,
      'rating' => rating,
      'experienceYears' => experience_years,
      'strongAreas' => strong_area_ids,
      'address' => address,
      'status' => status,
      'territory' => territory,
      'bookings' => bookings,
      'revenue' => revenue,
      'conversionRate' => conversion_rate,
      'commissionRate' => commission_rate,
      'commissionEarned' => commission_earned,
      'pendingCommission' => pending_commission,
      'leadsAssigned' => leads_assigned,
      'joinedDate' => joined_date,
      'commissionMonthly' => commission_monthly,
      'tasks' => tasks,
      'attendance' => attendance,
      'propertiesSold' => properties_sold,
      'propertiesAssigned' => properties_assigned,
      'documents' => documents,
      'activityLog' => activity_log,
      'hasPassword' => !encoded_password.nil?,
    }
  end
end
