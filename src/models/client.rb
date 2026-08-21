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
  one_to_many :client_status_histories
  many_to_one :agent
  many_to_one :ram_member

  # Same additive-FK-alongside-the-slug sync as models/lead.rb's own
  # sync_agent_reference!/sync_ram_reference! — see that file's comment.
  # Field names differ here (`assigned_agent_slug`/`assigned_ram_id`, both
  # slugs despite the latter's name — migrations/0017) but the logic is
  # identical.
  def before_validation
    if new?
      if agent_id.present?
        self.assigned_agent_slug = App::Models::Agent[agent_id]&.slug
      elsif assigned_agent_slug.present?
        self.agent_id = App::Models::Agent.where(slug: assigned_agent_slug).first&.id
      end
      if ram_member_id.present?
        self.assigned_ram_id = App::Models::RamMember[ram_member_id]&.slug
      elsif assigned_ram_id.present?
        self.ram_member_id = App::Models::RamMember.where(slug: assigned_ram_id).first&.id
      end
    else
      if column_changed?(:agent_id)
        self.assigned_agent_slug = agent_id.present? ? App::Models::Agent[agent_id]&.slug : nil
      elsif column_changed?(:assigned_agent_slug)
        self.agent_id = assigned_agent_slug.present? ? App::Models::Agent.where(slug: assigned_agent_slug).first&.id : nil
      end
      if column_changed?(:ram_member_id)
        self.assigned_ram_id = ram_member_id.present? ? App::Models::RamMember[ram_member_id]&.slug : nil
      elsif column_changed?(:assigned_ram_id)
        self.ram_member_id = assigned_ram_id.present? ? App::Models::RamMember.where(slug: assigned_ram_id).first&.id : nil
      end
    end
    super
  end

  # "Which Lead created this Client?" (the reverse of Lead#client) — a
  # client can in principle be reached from more than one Lead row over
  # time (e.g. a returning contact who enquires again after already
  # converting), so this resolves to the earliest one, the one that
  # actually produced the account via services/leads.rb#convert_to_client.
  def originating_lead
    App::Models::Lead.where(client_id: id).order(:created_at).first
  end

  # Ordered, real audit trail of every status change — written server-side,
  # insert-only (services/clients.rb#create/#update, services/agent_portal.rb#
  # update_my_client), never trusting a client-supplied history row. Same
  # shape/reasoning as Lead#status_history; distinct from #communication_log,
  # which stays freeform/client-supplied.
  def status_history
    client_status_histories_dataset.order(:created_at).all.map(&:to_pos)
  end

  # Read shape used by the Admin Portal (services/clients.rb) and Agent
  # Portal (services/agent_portal.rb) — both already read Client via the
  # generic `to_pos`, not the bespoke camelCase `as_pos` below (that one's
  # reserved for the Client Portal's own login/session/profile flow, see
  # services/client_auth.rb). Same "merge computed data into to_pos"
  # convention as Lead#with_status_history/Deal#with_status_history.
  def with_status_history
    to_pos.merge('status_history' => status_history)
  end

  # Property ids this client has actually purchased (invested_properties,
  # migrations/0017) — shared by anything that needs to tell "does this
  # client already own this property" apart from just being interested in
  # it: services/client_reviews.rb's own review-ownership check, and
  # services/client_site_visits.rb's "don't let someone re-book a site
  # visit on a property they already bought" guard. Was previously
  # duplicated as a private method inside client_reviews.rb alone.
  def owned_property_ids
    (invested_properties || []).map { |p| p['propertyId'] || p[:propertyId] }.compact.map(&:to_i)
  end

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
    validates_format(EMAIL_REGEXP, :email, message: 'is not a valid email address') if email && !email.strip.empty?
    validates_unique(:email)
    errors.add(:phone, 'must be a 10-digit phone number') if phone && !phone.strip.empty? && phone.gsub(/\D/, '').length != 10
    if assigned_ram_id.present? && (new? || column_changed?(:assigned_ram_id)) && App::Models::RamMember.where(slug: assigned_ram_id).first.nil?
      errors.add(:assigned_ram_id, 'must match an existing RAM team member')
    end
    if assigned_agent_slug.present? && (new? || column_changed?(:assigned_agent_slug)) && App::Models::Agent.where(slug: assigned_agent_slug).first.nil?
      errors.add(:assigned_agent_slug, 'must match an existing agent')
    end
  end

  # Called after every save from services/clients.rb — #create calls this
  # unconditionally (a client entered with an agent already picked is
  # always a fresh assignment), #update calls it only when the caller has
  # already determined `assigned_agent_slug` actually changed (computed
  # *before* the save, same "compare the incoming value to the pre-save
  # value" convention as Commissions#update's own `status_changing` —
  # deliberately NOT `column_changed?`, since that only reflects changes
  # made after a record is loaded and is always false for values set via
  # `.new` at creation, which would silently break the #create call site).
  # Notifies both sides of the same event: the agent gets told a new client
  # landed in their book of business, and the client gets told who their
  # advisor now is — distinct from, and in addition to, #update's own
  # generic "Your profile was updated" notification, which fires on any
  # profile edit, not just this one.
  def notify_of_agent_assignment!
    return if assigned_agent_slug.blank?

    agent = App::Models::Agent.where(slug: assigned_agent_slug).first
    return if agent.nil?

    App::Models::Notification.create(
      audience: 'agent',
      recipient_id: agent.id,
      type: 'client',
      icon: 'UserPlus',
      title: 'New client assigned',
      message: "A new client has been assigned to you: #{name}."
    )
    App::Models::Notification.create(
      audience: 'client',
      recipient_id: id,
      type: 'account',
      icon: 'UserCog',
      title: 'Agent assigned',
      message: "#{agent.name} has been assigned to you as your advisor."
    )
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
    end

    App::MailerTemplate.brand!(
      mail,
      preheader: "We received a request to reset your REROCK Realty password.",
      body_html: <<~HTML,
        <h2 style="margin:0 0 12px; font-size:20px; color:#1c1b1a;">Reset your password</h2>
        <p style="margin:0 0 8px;">Hello #{client_name},</p>
        <p style="margin:0;">We received a request to reset your REROCK Realty client portal password. Use the button below to choose a new one — this link expires shortly for your security.</p>
      HTML
      cta: { label: 'Reset your password', url: reset_url },
      footnote: 'If you did not request a password reset, you can safely ignore this email — your password will not be changed.'
    )

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
    end

    App::MailerTemplate.brand!(
      mail,
      preheader: "Your REROCK Realty client portal account is ready.",
      body_html: <<~HTML,
        <h2 style="margin:0 0 12px; font-size:20px; color:#1c1b1a;">Welcome to REROCK Realty</h2>
        <p style="margin:0 0 8px;">Hello #{client_name},</p>
        <p style="margin:0;">An account has been created for you on the REROCK Realty client portal. Here is your temporary password:</p>
        #{App::MailerTemplate.code_block(temp_password)}
        <p style="margin:0; font-size:13px; color:#6b6b6b;">Please log in and change your password from your profile settings as soon as possible.</p>
      HTML
    )

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
    end

    App::MailerTemplate.brand!(
      mail,
      preheader: "Your REROCK Realty verification code is #{code}",
      body_html: <<~HTML,
        <h2 style="margin:0 0 12px; font-size:20px; color:#1c1b1a;">Verify your email</h2>
        <p style="margin:0 0 4px;">Hello #{client_name},</p>
        <p style="margin:0;">Use the code below to verify your REROCK Realty client portal account:</p>
        #{App::MailerTemplate.code_block(code)}
        <p style="margin:0; font-size:13px; color:#6b6b6b;">This code expires in 10 minutes.</p>
      HTML
      footnote: 'If you did not create a REROCK Realty account, you can safely ignore this email.'
    )

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
      # Real FKs (migrations/0090), kept in lockstep with the two deferred
      # strings above by this model's own before_validation sync hook — the
      # Client Portal (lib/queries/client.js's useMyAssignedAgent/Ram) now
      # matches against these instead of the slug fields.
      'assignedAgentId' => agent_id,
      'assignedRamMemberId' => ram_member_id,
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
