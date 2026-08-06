require 'uri'

# The Agent Portal's own self-service auth (register/login/forgot-password/
# reset-password/profile) — deliberately a separate service from
# App::Services::Agents (services/agents.rb), which is the Admin Portal's
# staff-only CRUD over the same `agents` table. That one stays
# admin_required!-gated and untouched; this one is reachable by an agent's
# own CurrentAgent-issued token (or, for register/login/forgot/reset, no
# token at all — see routes.rb's public 'agent-portal' block).
#
# `model` is Agent (same table as Agents) purely so Base#save's audit-log
# hook and data_for(:save) whitelisting both work unchanged.
class App::Services::AgentAuth < App::Services::Base
  def model; Agent; end

  RESET_TOKEN_EXPIRATION_TIME = 2 * 60 * 60

  # Self-registration lands as `status: "Pending"` — same admin-must-approve
  # gate as RAM Portal's own self-registration (services/ram_auth.rb#register).
  # A fresh registration is deliberately NOT auto-logged-in. An admin can
  # still create an agent directly via /admin/agents (services/agents.rb),
  # in which case they start with no password at all and use the same
  # forgot-password link as a reset to set one — see #login's comment.
  def register
    name = params[:name]&.strip
    email = params[:email]&.strip&.downcase
    phone = params[:phone]&.strip
    password = params[:password]

    return_errors!("Name, email and password are required.", 400) if name.blank? || email.blank? || password.blank?
    return_errors!("Enter a valid email address.", 400) unless email.match?(URI::MailTo::EMAIL_REGEXP)
    return_errors!("Password must be at least 8 characters.", 400) if password.length < 8
    return_errors!("An account with this email already exists.", 400) if Agent.where(email: email).first

    agent = Agent.new(
      slug: unique_slug(name),
      name: name,
      email: email,
      phone: phone,
      role: "Agent",
      specialization: params[:specialization].presence,
      status: "Pending"
    )
    agent.password = password
    save(agent) { |o| return_success(o.as_pos) }
  end

  # No OTP/2FA step: a correct password logs an agent straight in, same as
  # every other portal's login. Gated on `status` exactly like RAM Portal's
  # login (services/ram_auth.rb#login) — "Pending" (fresh self-registration,
  # not yet admin-approved) and "Inactive" (deactivated) both block sign-in.
  def login
    email = params[:email]&.strip&.downcase
    agent = email.present? ? Agent.find(email: email) : nil

    return_errors!("Invalid Email / Password") if agent.nil?
    return_errors!("Your account doesn't have a password set yet. Use \"Forgot password\" to set one.") if agent.encoded_password.nil?
    return_errors!("Invalid Email / Password") unless agent.password == params[:password]

    if agent.status == "Pending"
      return_errors!("Your account is pending admin approval. You'll be able to sign in once it's approved.")
    elsif agent.status == "Inactive"
      return_errors!("This account has been deactivated. Contact an admin for access.")
    end

    agent.last_logged_in_at = Time.now
    agent.current_session_id = CurrentAgent.encoded_token(agent)
    unless agent.save
      return_errors!(agent.errors, 400)
    end
    return_success(token: agent.current_session_id, info: agent.as_pos)
  rescue => e
    App.logger.error(e.message)
    App.logger.error(e.backtrace)
    return_errors!("Some error occurred while signing in.")
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

  def unique_slug(name)
    base = name.to_s.downcase.strip.gsub(/[^a-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')
    base = "agent" if base.blank?
    "#{base}-#{SecureRandom.hex(3)}"
  end
end
