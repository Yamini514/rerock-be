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

  # Called after every save from the admin update path
  # (services/agents.rb#update) — same "call unconditionally after save,
  # guard with an actual-change check" convention as
  # SiteVisit#notify_client_of_status!/Deal#notify_client_of_closure!. Only
  # fires on the specific Pending -> Active transition (the real approval
  # moment, e.g. AgentsPage's "Approve" action) — not, say, an Inactive ->
  # Active reactivation toggle elsewhere on the Agent Detail page, which
  # isn't a "your registration was approved" event.
  def notify_of_approval!
    return unless column_changed?(:status)
    return unless initial_value(:status) == 'Pending' && status == 'Active'

    App::Models::Notification.create(
      audience: 'agent',
      recipient_id: id,
      type: 'account',
      icon: 'CheckCircle2',
      title: 'Registration approved',
      message: 'Your registration has been approved. You can now log in to your account.'
    )
    send_approval_email(ENV['AGENT_APP_URL'] || 'http://localhost:3000/agent')
  end

  # The notice that actually reaches the agent in time — unlike the in-app
  # Notification above, which sits behind agent_auth_required! and so can't
  # be seen until *after* a first successful login, email works before
  # they're able to log in at all (agent_auth.rb#login blocks sign-in while
  # status is still "Pending"), same "email is the only channel that works
  # pre-login" reasoning as Client#send_temporary_password_email. No
  # password/reset link needed here — a self-registered agent already set
  # their own password at registration (see #register above), they just
  # need to know it's time to use it.
  def send_approval_email(base_url)
    agent_email = self.email
    agent_name = self.name
    login_url = "#{base_url}/login"

    mail = Mail.new do
      from    'apps@srinishtha.com'
      to      agent_email
      subject 'Your REROCK Realty agent account is approved'
      html_part do
        content_type 'text/html; charset=UTF-8'
        body <<-HTML
          <html>
          <body>
            <h1>You're approved!</h1>
            <p>Hello #{agent_name},</p>
            <p>Your REROCK Realty agent registration has been approved. You can now log in to your account.</p>
            <p><a href="#{login_url}">Log in</a></p>
            <p>Thank you,<br/>REROCK Realty</p>
          </body>
          </html>
        HTML
      end
    end

    mail.deliver!
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
