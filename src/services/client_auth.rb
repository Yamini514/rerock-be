require 'uri'

# The Client Portal's own self-service auth (register/verify-otp/login/
# forgot-password/reset-password/profile) — deliberately a separate service
# from App::Services::Clients (services/clients.rb), which is the Admin
# Portal's staff-only CRM CRUD over the same `clients` table. That one stays
# admin_required!-gated and untouched; this one is reachable by a client's
# own CurrentClient-issued token (or, for register/verify-otp/login/forgot/
# reset, no token at all — see routes.rb's public 'client-portal' block).
#
# `model` is Client (same table as Clients) purely so Base#save's audit-log
# hook and data_for(:save) whitelisting both work unchanged.
class App::Services::ClientAuth < App::Services::Base
  def model; Client; end

  RESET_TOKEN_EXPIRATION_TIME = 2 * 60 * 60
  OTP_EXPIRATION_TIME = 10 * 60

  NAME_MAX_LENGTH = 60
  NAME_REGEXP = /\A[a-zA-Z\s'.-]+\z/
  PHONE_REGEXP = /\A[6-9]\d{9}\z/

  # Registration creates the row immediately (unlike RamAuth#register's
  # "Pending admin approval" gate — a retail client browsing/tracking their
  # own portfolio doesn't need admin vetting the way an advisory member
  # does) but leaves `email_verified_at` nil and sends a real OTP email;
  # `login` below blocks until that's set. An optional `referral_code`
  # resolves `referred_by_id` against another client's own code.
  def register
    name = params[:name]&.strip
    email = params[:email]&.strip&.downcase
    phone = params[:phone]&.strip
    password = params[:password]

    return_errors!("Name, email, phone and password are required.", 400) if name.blank? || email.blank? || phone.blank? || password.blank?
    return_errors!("Enter a valid email address.", 400) unless email.match?(URI::MailTo::EMAIL_REGEXP)
    return_errors!("Name must be #{NAME_MAX_LENGTH} characters or fewer.", 400) if name.length > NAME_MAX_LENGTH
    return_errors!("Name can only contain letters, spaces, apostrophes and hyphens.", 400) unless name.match?(NAME_REGEXP)
    return_errors!("Enter a valid 10-digit mobile number.", 400) unless phone.match?(PHONE_REGEXP)
    return_errors!("Password must be at least 8 characters.", 400) if password.length < 8
    return_errors!("An account with this email already exists.", 400) if Client.where(email: email).first

    referrer = params[:referral_code].present? ? Client.where(referral_code: params[:referral_code].strip).first : nil

    client = Client.new(
      name: name,
      email: email,
      phone: phone,
      city: params[:city],
      type: params[:type].presence || "Individual",
      referral_source: referrer ? "Referral" : params[:referral_source],
      referred_by_id: referrer&.id,
      referral_code: unique_referral_code
    )
    client.password = password

    save(client) do |o|
      o.generate_and_send_otp!
      return_success(email: o.email)
    end
  end

  def verify_otp
    email = params[:email]&.strip&.downcase
    code = params[:code]&.strip
    return_errors!("Email and code are required.", 400) if email.blank? || code.blank?

    client = Client.where(email: email).first
    return_errors!("No account found with that email.", 404) if client.nil?
    return_errors!("Already verified — you can sign in.", 400) if client.email_verified_at

    unless client.otp_code == code && otp_valid?(client)
      return_errors!("Invalid or expired code.")
    end

    client.email_verified_at = Time.now
    client.otp_code = nil
    client.otp_sent_at = nil
    client.current_session_id = CurrentClient.encoded_token(client)
    unless client.save
      return_errors!(client.errors, 400)
    end
    return_success(token: client.current_session_id, info: client.as_pos)
  end

  def resend_otp
    email = params[:email]&.strip&.downcase
    return_errors!("Email is required.", 400) if email.blank?

    client = Client.where(email: email).first
    return_errors!("No account found with that email.", 404) if client.nil?
    return_errors!("Already verified — you can sign in.", 400) if client.email_verified_at

    client.generate_and_send_otp!
    return_success("A new code has been sent to #{client.email}")
  end

  def login
    email = params[:email]&.strip&.downcase
    client = email.present? ? Client.find(email: email) : nil

    return_errors!("Invalid Email / Password") unless client && client.password == params[:password]
    return_errors!("Please verify your email before signing in.", 403) if client.email_verified_at.nil?

    if client.status == "Inactive"
      return_errors!("This account has been deactivated. Contact support for access.")
    end

    client.last_logged_in_at = Time.now
    client.current_session_id = CurrentClient.encoded_token(client)
    unless client.save
      return_errors!(client.errors, 400)
    end
    return_success(token: client.current_session_id, info: client.as_pos)
  rescue => e
    App.logger.error(e.message)
    App.logger.error(e.backtrace)
    return_errors!("Some error occurred while signing in.")
  end

  # Authenticated (client_auth_required!) — the currently logged-in client's
  # own profile. No `id`-parameterized "get any client" action here at all
  # (unlike Clients#get) — self-service only.
  def info
    return_errors!("Not signed in.", 401) if CurrentClient.client_obj.nil?
    return_success(CurrentClient.client_obj.as_pos)
  end

  # Whitelisted narrower than Clients#fields' save list on purpose: a client
  # can edit their own display/contact info and append to their own
  # notes/communication_log/timeline (same "frontend sends the whole array
  # back, already-appended" convention as everywhere else) — but NOT their
  # own status/assigned_agent_slug/assigned_ram_id/referred_by_id, which stay
  # admin-managed-only (Clients, via /admin/clients). `invested_properties`
  # is intentionally excluded too: a client shouldn't be able to add a
  # holding to their own portfolio by editing their profile — that's an
  # admin/advisor action recording a real transaction.
  def update_profile
    client = CurrentClient.client_obj
    return_errors!("Not signed in.", 401) if client.nil?

    allowed = params.slice(:name, :email, :phone, :avatar, :city, :type, :notes, :communication_log, :timeline)

    if allowed[:email].present?
      new_email = allowed[:email].strip.downcase
      return_errors!("Enter a valid email address.", 400) unless new_email.match?(URI::MailTo::EMAIL_REGEXP)
      return_errors!("An account with this email already exists.", 400) if Client.where(email: new_email).exclude(id: client.id).first
      allowed[:email] = new_email
    end

    if allowed[:name].present?
      new_name = allowed[:name].strip
      return_errors!("Name must be #{NAME_MAX_LENGTH} characters or fewer.", 400) if new_name.length > NAME_MAX_LENGTH
      return_errors!("Name can only contain letters, spaces, apostrophes and hyphens.", 400) unless new_name.match?(NAME_REGEXP)
      allowed[:name] = new_name
    end

    if allowed[:phone].present?
      new_phone = allowed[:phone].strip
      return_errors!("Enter a valid 10-digit mobile number.", 400) unless new_phone.match?(PHONE_REGEXP)
      allowed[:phone] = new_phone
    end

    client.set_fields(allowed, allowed.keys)
    save(client) { |o| return_success(o.as_pos) }
  end

  def update_password
    client = CurrentClient.client_obj
    return_errors!("Not signed in.", 401) if client.nil?

    if client.password != params[:current_password]
      return_errors!("Invalid current password.")
    elsif params[:new_password] == params[:current_password]
      return_errors!("New password must be different from your current password.")
    else
      client.password = params[:new_password]
      save(client) { return_success("Password updated successfully.") }
    end
  end

  def forgot_password
    email = params[:email]&.strip&.downcase
    return_errors!("Email is required.", 400) if email.blank?

    client = Client.where(email: email).first
    if client
      client.send_password_reset_email(ENV['CLIENT_APP_URL'] || 'http://localhost:3000/portal')
      return_success("Password reset email sent to #{client.email}")
    else
      return_errors!("No account found with email: #{email}", 404)
    end
  end

  def validate_password_token
    token = params[:token]
    return_errors!('Token is missing.', 400) if token.blank?

    client = Client.where(reset_token: token).first
    if client && token_valid?(client)
      return_success('Token is valid.')
    else
      return_errors!('Invalid or expired token.')
    end
  end

  def reset_password
    token = params[:token]
    new_password = params[:password]
    return_errors!('Token and new password are required.', 400) if token.blank? || new_password.blank?

    client = Client.where(reset_token: token).first
    if client && token_valid?(client)
      client.password = new_password
      client.reset_token = nil
      client.reset_sent_at = nil
      save(client) { return_success('Password has been reset.') }
    else
      return_errors!('Invalid or expired token.', 400)
    end
  end

  private

  def token_valid?(client)
    return false if client.reset_sent_at.nil?

    (Time.now - client.reset_sent_at) < RESET_TOKEN_EXPIRATION_TIME
  end

  def otp_valid?(client)
    return false if client.otp_sent_at.nil?

    (Time.now - client.otp_sent_at) < OTP_EXPIRATION_TIME
  end

  def unique_referral_code
    loop do
      code = "REF-#{SecureRandom.alphanumeric(6).upcase}"
      break code unless Client.where(referral_code: code).first
    end
  end
end
