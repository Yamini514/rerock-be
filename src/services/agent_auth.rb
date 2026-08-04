require 'uri'

# The Agent Portal's own self-service auth (login/verify-otp/resend-otp/
# forgot-password/reset-password/profile) — deliberately a separate service
# from App::Services::Agents (services/agents.rb), which is the Admin
# Portal's staff-only CRUD over the same `agents` table. That one stays
# admin_required!-gated and untouched; this one is reachable by an agent's
# own CurrentAgent-issued token (or, for login/verify-otp/resend-otp/forgot/
# reset, no token at all — see routes.rb's public 'agent-portal' block).
#
# No #register: agents are provisioned by an admin via /admin/agents, never
# self-register (matches the frontend — there's no Agent Portal register
# page, unlike the Client Portal's). An agent's first-ever password is set
# through the exact same forgot-password link as a reset — see #login's
# comment for why that's a deliberate, sufficient substitute for a real
# "invite" flow.
#
# `model` is Agent (same table as Agents) purely so Base#save's audit-log
# hook and data_for(:save) whitelisting both work unchanged.
class App::Services::AgentAuth < App::Services::Base
  def model; Agent; end

  RESET_TOKEN_EXPIRATION_TIME = 2 * 60 * 60
  OTP_EXPIRATION_TIME = 10 * 60

  # Two-factor: this only checks the password and, if correct, emails a
  # fresh OTP — it does NOT issue a session token (matching the existing
  # frontend flow, where AgentLoginPage always redirects to verify-otp
  # rather than logging in directly). #verify_otp below is what actually
  # issues the token. Since #resend_otp re-checks the password too (not just
  # the email), an OTP can never be (re)sent to someone who doesn't already
  # know the password — the two factors stay genuinely independent.
  def login
    email = params[:email]&.strip&.downcase
    agent = email.present? ? Agent.find(email: email) : nil

    return_errors!("Invalid Email / Password") if agent.nil?
    return_errors!("Your account doesn't have a password set yet. Use \"Forgot password\" to set one.") if agent.encoded_password.nil?
    return_errors!("Invalid Email / Password") unless agent.password == params[:password]
    return_errors!("This account has been deactivated. Contact an admin for access.") if agent.status == "Inactive"

    agent.generate_and_send_otp!
    return_success(email: agent.email)
  rescue => e
    App.logger.error(e.message)
    App.logger.error(e.backtrace)
    return_errors!("Some error occurred while signing in.")
  end

  def resend_otp
    email = params[:email]&.strip&.downcase
    agent = email.present? ? Agent.find(email: email) : nil

    return_errors!("Invalid Email / Password") unless agent && agent.encoded_password && agent.password == params[:password]

    agent.generate_and_send_otp!
    return_success("A new code has been sent to #{agent.email}")
  end

  def verify_otp
    email = params[:email]&.strip&.downcase
    code = params[:code]&.strip
    return_errors!("Email and code are required.", 400) if email.blank? || code.blank?

    agent = Agent.where(email: email).first
    return_errors!("No account found with that email.", 404) if agent.nil?

    unless agent.otp_code == code && otp_valid?(agent)
      return_errors!("Invalid or expired code.")
    end

    agent.otp_code = nil
    agent.otp_sent_at = nil
    agent.last_logged_in_at = Time.now
    agent.current_session_id = CurrentAgent.encoded_token(agent)
    unless agent.save
      return_errors!(agent.errors, 400)
    end
    return_success(token: agent.current_session_id, info: agent.as_pos)
  end

  # Authenticated (agent_auth_required!) — the currently logged-in agent's
  # own profile. No `id`-parameterized "get any agent" action here at all
  # (unlike Agents#get) — self-service only.
  def info
    return_errors!("Not signed in.", 401) if CurrentAgent.agent_obj.nil?
    return_success(CurrentAgent.agent_obj.as_pos)
  end

  # Whitelisted narrower than Agents#fields' save list on purpose: an agent
  # can edit their own display/contact info and append to their own
  # tasks/attendance/documents/activity_log (same "frontend sends the whole
  # array back, already-appended" convention as everywhere else) — but NOT
  # their own status/territory/bookings/revenue/commission_*/leads_assigned/
  # properties_sold/properties_assigned, which stay admin-managed-only
  # (Agents, via /admin/agents) so an agent can't self-inflate their own
  # KPIs or reassign their own book of business.
  def update_profile
    agent = CurrentAgent.agent_obj
    return_errors!("Not signed in.", 401) if agent.nil?

    allowed = params.slice(:name, :email, :phone, :whatsapp, :avatar, :specialization, :address, :tasks, :attendance, :documents, :activity_log)

    if allowed[:email].present?
      new_email = allowed[:email].strip.downcase
      return_errors!("Enter a valid email address.", 400) unless new_email.match?(URI::MailTo::EMAIL_REGEXP)
      return_errors!("An account with this email already exists.", 400) if Agent.where(email: new_email).exclude(id: agent.id).first
      allowed[:email] = new_email
    end

    agent.set_fields(allowed, allowed.keys)
    save(agent) { |o| return_success(o.as_pos) }
  end

  def update_password
    agent = CurrentAgent.agent_obj
    return_errors!("Not signed in.", 401) if agent.nil?

    if agent.encoded_password && agent.password == params[:current_password]
      agent.password = params[:new_password]
      save(agent) { return_success("Password updated successfully.") }
    else
      return_errors!("Invalid current password.")
    end
  end

  def forgot_password
    email = params[:email]&.strip&.downcase
    return_errors!("Email is required.", 400) if email.blank?

    agent = Agent.where(email: email).first
    if agent
      agent.send_password_reset_email(ENV['AGENT_APP_URL'] || 'http://localhost:3000/agent')
      return_success("Password reset email sent to #{agent.email}")
    else
      return_errors!("No account found with email: #{email}", 404)
    end
  end

  def validate_password_token
    token = params[:token]
    return_errors!('Token is missing.', 400) if token.blank?

    agent = Agent.where(reset_token: token).first
    if agent && token_valid?(agent)
      return_success('Token is valid.')
    else
      return_errors!('Invalid or expired token.')
    end
  end

  def reset_password
    token = params[:token]
    new_password = params[:password]
    return_errors!('Token and new password are required.', 400) if token.blank? || new_password.blank?

    agent = Agent.where(reset_token: token).first
    if agent && token_valid?(agent)
      agent.password = new_password
      agent.reset_token = nil
      agent.reset_sent_at = nil
      save(agent) { return_success('Password has been set.') }
    else
      return_errors!('Invalid or expired token.', 400)
    end
  end

  private

  def token_valid?(agent)
    return false if agent.reset_sent_at.nil?

    (Time.now - agent.reset_sent_at) < RESET_TOKEN_EXPIRATION_TIME
  end

  def otp_valid?(agent)
    return false if agent.otp_sent_at.nil?

    (Time.now - agent.otp_sent_at) < OTP_EXPIRATION_TIME
  end
end
