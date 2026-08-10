require 'uri'

# The RAM Portal's own self-service auth (register/login/forgot-password/
# reset-password/profile) — deliberately a separate service from
# App::Services::RamMembers (services/ram_members.rb), which is the
# Admin Portal's staff-only CRUD over the same `ram_members` table. That one
# stays admin_required!-gated and untouched; this one is reachable by a RAM
# member's own CurrentRam-issued token (or, for register/login/forgot/reset,
# no token at all — see routes.rb's public 'ram-portal' block).
#
# `model` is RamMember (same table as RamMembers) purely so Base#save's
# audit-log hook and data_for(:save) whitelisting both work unchanged.
class App::Services::RamAuth < App::Services::Base
  def model; RamMember; end

  RESET_TOKEN_EXPIRATION_TIME = 2 * 60 * 60
  PHONE_REGEXP = /\A[6-9]\d{9}\z/

  # Self-registration lands as `status: "Pending"` (RAM_STATUSES in
  # lib/data/staff.js) — same "admin must approve" gate the old mock's login
  # page already enforced (see the frontend's own Pending/Inactive checks in
  # `login` below), just backed by a real row now instead of the ramTeam
  # array. A fresh registration is deliberately NOT auto-logged-in.
  def register
    name = params[:name]&.strip
    email = params[:email]&.strip&.downcase
    phone = params[:phone]&.strip
    password = params[:password]

    return_errors!("Name, email, phone and password are required.", 400) if name.blank? || email.blank? || phone.blank? || password.blank?
    return_errors!("Enter a valid email address.", 400) unless email.match?(URI::MailTo::EMAIL_REGEXP)
    return_errors!("Enter a valid 10-digit mobile number.", 400) unless phone.match?(PHONE_REGEXP)
    return_errors!("Password must be at least 8 characters.", 400) if password.length < 8
    return_errors!("An account with this email already exists.", 400) if RamMember.where(email: email).first

    # `phone`/`referral_code` have no dedicated columns on ram_members (they
    # never existed on the Admin-facing table, only on the portal's own
    # RamRegisterPage form) — folded into profile_extra alongside the rest
    # of the self-service-only contact/professional/bank/KYC fields, same
    # jsonb-blob convention as everywhere else in this build.
    ram = RamMember.new(
      slug: unique_slug(name),
      name: name,
      email: email,
      designation: params[:designation].presence || "RAM",
      region: params[:region].presence || "Unassigned",
      status: "Pending",
      profile_extra: { phone: phone, referralCode: params[:referral_code] }.compact
    )
    ram.password = password
    save(ram) do |o|
      Notification.create(
        audience: "ram",
        recipient_id: o.id,
        type: "welcome",
        icon: "PartyPopper",
        title: "Welcome to REROCK Realty",
        message: "Your RAM account has been created. Your RAM ID is #{o.slug}."
      )
      Notification.create(
        audience: "admin",
        type: "ram",
        icon: "UserPlus",
        title: "New RAM registration",
        message: "#{o.name} registered and is awaiting approval."
      )
      return_success(o.as_pos)
    end
  end

  def login
    email = params[:email]&.strip&.downcase
    ram = email.present? ? RamMember.find(email: email) : nil

    return_errors!("Invalid Email / Password") unless ram && ram.password == params[:password]

    if ram.status == "Pending"
      return_errors!("Your account is pending admin approval. You'll be able to sign in once it's approved.")
    elsif ram.status == "Inactive"
      return_errors!("This account has been deactivated. Contact an admin for access.")
    end

    ram.last_logged_in_at = Time.now
    ram.current_session_id = CurrentRam.encoded_token(ram)
    unless ram.save
      return_errors!(ram.errors, 400)
    end
    return_success(token: ram.current_session_id, info: ram.as_pos)
  rescue => e
    App.logger.error(e.message)
    App.logger.error(e.backtrace)
    return_errors!("Some error occurred while signing in.")
  end

  # Authenticated (ram_auth_required!) — the currently logged-in RAM member's
  # own profile. There is no `id`-parameterized "get any RAM member" action
  # here at all (unlike RamMembers#get) — self-service only.
  def info
    return_errors!("Not signed in.", 401) if CurrentRam.ram_obj.nil?
    return_success(CurrentRam.ram_obj.as_pos)
  end

  # Whitelisted narrower than RamMembers#fields' save list on purpose: a RAM
  # member can edit their own display info, extended profile (contact/bank/
  # KYC via profile_extra), and append to their own recommendations/
  # documents/activities arrays (same "frontend sends the whole array back,
  # already-appended" convention as everywhere else in this codebase) — but
  # NOT their own status/builder_ids/revenue_managed/performance/
  # satisfaction/renewal_rate/conversion_rate_pct/etc. — those stay
  # admin-managed-only (RamMembers, via /admin/ram) so a member can't
  # self-inflate their own KPIs. `email`/`experience_years` ARE included:
  # neither is a gameable performance number, and the old mock's own
  # ProfileClient already let a member edit both directly.
  def update_profile
    ram = CurrentRam.ram_obj
    return_errors!("Not signed in.", 401) if ram.nil?

    allowed = params.slice(
      :name, :email, :avatar, :designation, :region, :experience_years,
      :recommendations, :documents, :activities, :profile_extra
    )

    if allowed[:email].present?
      new_email = allowed[:email].strip.downcase
      return_errors!("Enter a valid email address.", 400) unless new_email.match?(URI::MailTo::EMAIL_REGEXP)
      return_errors!("An account with this email already exists.", 400) if RamMember.where(email: new_email).exclude(id: ram.id).first
      allowed[:email] = new_email
    end

    ram.set_fields(allowed, allowed.keys)
    save(ram) do |o|
      Notification.create(
        audience: "ram",
        recipient_id: o.id,
        type: "profile",
        icon: "UserCog",
        title: "Profile updated",
        message: "Your personal information has been updated successfully."
      )
      return_success(o.as_pos)
    end
  end

  def update_password
    ram = CurrentRam.ram_obj
    return_errors!("Not signed in.", 401) if ram.nil?

    if ram.password == params[:current_password]
      ram.password = params[:new_password]
      ram.must_change_password = false
      save(ram) { return_success("Password updated successfully.") }
    else
      return_errors!("Invalid current password.")
    end
  end

  def forgot_password
    email = params[:email]&.strip&.downcase
    return_errors!("Email is required.", 400) if email.blank?

    ram = RamMember.where(email: email).first
    if ram
      ram.send_password_reset_email(ENV['RAM_APP_URL'] || 'http://localhost:3000/ram')
      return_success("Password reset email sent to #{ram.email}")
    else
      return_errors!("No account found with email: #{email}", 404)
    end
  end

  def validate_password_token
    token = params[:token]
    return_errors!('Token is missing.', 400) if token.blank?

    ram = RamMember.where(reset_token: token).first
    if ram && token_valid?(ram)
      return_success('Token is valid.')
    else
      return_errors!('Invalid or expired token.')
    end
  end

  def reset_password
    token = params[:token]
    new_password = params[:password]
    return_errors!('Token and new password are required.', 400) if token.blank? || new_password.blank?

    ram = RamMember.where(reset_token: token).first
    if ram && token_valid?(ram)
      ram.password = new_password
      ram.reset_token = nil
      ram.reset_sent_at = nil
      ram.must_change_password = false
      save(ram) { return_success('Password has been reset.') }
    else
      return_errors!('Invalid or expired token.', 400)
    end
  end

  private

  def token_valid?(ram)
    return false if ram.reset_sent_at.nil?

    (Time.now - ram.reset_sent_at) < RESET_TOKEN_EXPIRATION_TIME
  end

  def unique_slug(name)
    base = name.to_s.downcase.strip.gsub(/[^a-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')
    base = "ram-member" if base.blank?
    "#{base}-#{SecureRandom.hex(3)}"
  end
end
