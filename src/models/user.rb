class App::Models::User < Sequel::Model
  include BCrypt

  many_to_one :role
  # Self-referential FK (migrations/0039) backing the mock's reportingTo — the
  # frontend resolves this to a display name by looking the id up against the
  # fetched Users list (same "resolve on the frontend" convention as every
  # other cross-resource id array elsewhere in this build), so no association
  # method is actually called from any service; kept here anyway since it's
  # the correct, idiomatic Sequel shape for the column and costs nothing.
  many_to_one :reporting_to, class: self

  def validate
    super
    validates_presence [:full_name, :email]
    validates_unique(:email) { |ds| ds.where(active: true) }
  end

  def password
    @password ||= Password.new(encoded_password)
  end

  def password=(new_password)
    @password = Password.create(new_password)
    self.encoded_password = @password
  end

  # Resolves this user's effective permission flags: role's flags, plus any
  # per-user allow overrides, minus any deny overrides — same precedence as
  # the frontend mock's effectivePermissions() in lib/data/staff.js.
  def resolved_permissions
    return ['*'] if is_super_admin

    base = Array(role&.permissions)
    overrides = permission_overrides || {}
    allow = Array(overrides['allow'] || overrides[:allow])
    deny = Array(overrides['deny'] || overrides[:deny])
    ((base + allow) - deny).uniq
  end

  def generate_reset_token!
    self.reset_token = SecureRandom.urlsafe_base64
    self.reset_sent_at = Time.now
    save
  end

  def send_password_reset_email(base_url)
    generate_reset_token!

    user_email = self.email
    user_name = self.full_name
    reset_url = "#{base_url}/reset-password?token=#{CGI.escape(reset_token)}"

    mail = Mail.new do
      from    'apps@srinishtha.com'
      to      user_email
      subject 'Reset your password'
      html_part do
        content_type 'text/html; charset=UTF-8'
        body <<-HTML
          <html>
          <body>
            <h1>Reset your password</h1>
            <p>Hello #{user_name},</p>
            <p>We received a request to reset your password. Click the link below to reset it:</p>
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

  # Custom shape for the login response / /me/info — distinct from the generic
  # DefaultJson#to_pos, since AdminAuthContext needs role name + resolved flags,
  # not raw column dump (and never the password hash). Also the shape the
  # admin Users list/detail pages consume for every *other* user (not just the
  # logged-in one) — includes role_id (raw, for edit-form Selects) alongside
  # the resolved 'role' name string, plus the small set of profile fields
  # added in migrations/0039.
  def as_pos
    as_json(only: [
      :id, :full_name, :email, :active, :created_at, :updated_at,
      :phone_number, :designation, :department, :reporting_to_id,
      :last_logged_in_at, :role_id, :permission_overrides, :avatar_url
    ]).merge!(
      'role' => role&.name,
      'role_slug' => role&.slug,
      'is_super_admin' => is_super_admin == true,
      'permissions' => resolved_permissions
    )
  end
end
