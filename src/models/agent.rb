require 'uri'

class App::Models::Agent < Sequel::Model
  include BCrypt

  # No many_to_one/self-FK needed. `strong_area_ids` is a plain integer[]
  # column (like Property#tag_ids/#amenity_ids), not a Sequel association —
  # resolving it to full Area records happens on the frontend by filtering
  # areasApi's list against the id array (admin) or the public areas browse
  # endpoint (Agent Portal — routes.rb's 'public' block).

  # Platform default commission rate — matches the `commission_rate` column's
  # own DB default (migrations/0019) and mirrors Deal::DEFAULT_COMMISSION_RATE_PCT's
  # role for RAM: the value AgentAuth#register seeds a self-registered agent
  # with, since Sequel validation (below) runs against in-memory attributes
  # and never sees a column's DB-level default.
  DEFAULT_COMMISSION_RATE_PCT = 1.5

  PHONE_REGEXP = /\A[6-9]\d{9}\z/
  NAME_REGEXP = /\A[A-Za-z][A-Za-z\s.'-]*\z/

  # Role and Joined Date are no longer entered anywhere — not on the Admin
  # Portal's Add/Edit Agent form, not on self-registration
  # (AgentAuth#register used to set both explicitly; that duplicate logic is
  # gone now that this hook covers every creation path). Every brand-new
  # Agent gets `role: "Agent"` and `joined_date: today` stamped here, in
  # before_validation (not before_create), specifically so they're already
  # non-blank by the time #validate's presence checks run below — neither
  # field is in services/agents.rb's save whitelist anymore, so this is the
  # only place either ever gets set.
  def before_validation
    if new?
      self.role = "Agent"
      self.joined_date ||= Date.today
    end
    super
  end

  # Shaped exactly like RamMember#validate: fields that only the Admin
  # Portal's create/edit form ever sets are guarded with
  # `new? || column_changed?(:field)` rather than firing unconditionally —
  # this is what lets a plain status-only PUT (the list page's "Approve"
  # action, or AgentDetailClient's Activate/Deactivate toggle) keep working
  # on a legacy/self-registered record that predates this rule without ever
  # touching the field it doesn't have; the moment someone actually edits
  # that field, it has to resolve to a valid, non-blank value. Self-
  # registration (AgentAuth#register) is a `new?` save too, so it seeds
  # sensible defaults for territory/specialization/experience_years/
  # commission_rate itself — see that method's own comment. No role/
  # joined_date checks here — before_validation above guarantees both
  # unconditionally on every new record, so there's nothing left to check.
  def validate
    super
    validates_presence [:name, :email]
    validates_unique(:email)
    if name.present?
      errors.add(:name, "can only contain letters, spaces, hyphens, apostrophes and periods") unless name.match?(NAME_REGEXP)
      errors.add(:name, "must be 100 characters or less") if name.length > 100
    end
    errors.add(:email, "must be a valid email address") if email.present? && !email.match?(URI::MailTo::EMAIL_REGEXP)

    if new? || column_changed?(:phone)
      errors.add(:phone, "Can't be blank") if phone.blank?
      errors.add(:phone, "must be a valid 10-digit phone number") if phone.present? && !phone.match?(PHONE_REGEXP)
    end
    if new? || column_changed?(:territory)
      errors.add(:territory, "Can't be blank") if territory.blank?
    end
    if new? || column_changed?(:specialization)
      errors.add(:specialization, "Can't be blank") if specialization.blank?
    end
    if new? || column_changed?(:experience_years)
      errors.add(:experience_years, "Can't be blank") if experience_years.nil?
      errors.add(:experience_years, "must be a positive number") if experience_years.present? && experience_years.to_i <= 0
    end
    if new? || column_changed?(:commission_rate)
      errors.add(:commission_rate, "Can't be blank") if commission_rate.nil?
      errors.add(:commission_rate, "must be between 0 and 100") if commission_rate.present? && !(0..100).cover?(commission_rate.to_f)
    end
    if new? || column_changed?(:profession)
      errors.add(:profession, "Can't be blank") if profession.blank?
    end
    if new? || column_changed?(:date_of_birth)
      errors.add(:date_of_birth, "Can't be blank") if date_of_birth.nil?
    end
    errors.add(:date_of_birth, "must result in an age between 18 and 49") if date_of_birth.present? && age && !age.between?(18, 49)

    validate_strong_area_ids
  end

  # Not marked `private` — every other method in this file (live_stats,
  # as_pos, password=, etc.) is called externally from services/agents.rb,
  # so there's no existing `private` section to slot this into without
  # accidentally hiding those from their real callers.
  #
  # `strong_area_ids` is a plain Postgres integer[] column (see this file's
  # own comment above), so nothing at the DB level stops a stale/deleted
  # Area id from silently sitting in it — same "typo/deleted-record
  # shouldn't silently create an orphaned assignment" reasoning as
  # models/community.rb#validate_amenity_ids. `.to_a` matters here too: the
  # column comes back as a Sequel::Postgres::PGArray, and passing that
  # straight into `where(id: ...)` makes Sequel build a single
  # `"id" = ARRAY[...]::integer[]` comparison instead of an `IN (...)` list
  # (`integer = integer[]` has no such Postgres operator) — same bug already
  # fixed in models/community.rb/models/property.rb.
  def validate_strong_area_ids
    return unless strong_area_ids.present? && (new? || column_changed?(:strong_area_ids))

    ids = strong_area_ids.to_a
    valid_ids = App::Models::Area.where(id: ids).select_map(:id)
    invalid_ids = ids - valid_ids
    errors.add(:strong_area_ids, "references areas that don't exist: #{invalid_ids.join(', ')}") if invalid_ids.any?
  end

  # Derived from date_of_birth, not a stored/directly-typed column (see
  # migrations/0086) — this is what #validate's "must result in an age
  # between 18 and 49" check above reads, and what Agent#as_pos exposes as
  # `age` to every existing caller (Admin Portal, Agent Portal) unchanged.
  # nil when date_of_birth isn't set (a legacy record predating this rule).
  def age
    return nil if date_of_birth.nil?

    today = Date.today
    years = today.year - date_of_birth.year
    years -= 1 if today.month < date_of_birth.month || (today.month == date_of_birth.month && today.day < date_of_birth.day)
    years
  end

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

  # Real linkage exists for these via Lead#agent_slug / Deal#agent_slug
  # (migrations/0014/0018), so they're computed live on every read instead
  # of trusted from the stored column an admin's Edit Agent form used to
  # write (see services/agents.rb#update's now-shorter :save whitelist) —
  # same "compute live, don't trust the stored column" precedent as
  # FollowUp#with_overdue. `bookings` and `deals_closed` collapse into the
  # same number here: the mock had them as two separately-arbitrary counters
  # with no documented distinction, and there's only one real "closed deals
  # for this agent" figure to derive from now.
  #
  # commission_earned is now also computed live, from each closed deal's own
  # stamped Deal#agent_commission_amount (set once, at the moment that deal
  # first closed, by Deal#ensure_agent_commission_for_closure! — see that
  # method) rather than the flat admin-typed `commission_earned` column or
  # (as this used to do) the agent's *current* commission_rate applied
  # retroactively to every past deal. That old approach meant editing an
  # agent's commission_rate today silently rewrote every prior month's
  # commission — the opposite of "changing the rate later shouldn't change
  # historical commissions." A closed deal that predates this column (so
  # `agent_commission_amount` is nil) falls back to the same current-rate
  # estimate as before, purely so pre-existing data doesn't suddenly show
  # ₹0 — every deal closed from here on gets a real stamped amount.
  # pending_commission is now also computed live: the anticipated commission
  # on this agent's still-open deals (any stage other than "Closed" —
  # Opportunity/Proposal/Negotiation/Booking, see lib/data/deals.js's
  # DEAL_STAGES) at the agent's *current* commission_rate. Unlike
  # commission_earned above, there's nothing to "lock in" here — an open
  # deal hasn't closed yet, so its anticipated commission should track the
  # agent's current rate until the day it actually closes and gets stamped.
  #
  # rating is now also computed live, from this agent's own approved client
  # reviews (Review#reviewable_type/#reviewable_id, same polymorphic shape
  # Property/Builder/Community reviews use — see ReviewsSection.js's
  # identical client-side average for the precedent this mirrors) rather
  # than a flat admin-typed number; 0 with no reviews yet, same "no data yet"
  # convention as conversion_rate below.
  def live_stats
    @live_stats ||= begin
      closed_deals = App::Models::Deal.where(agent_slug: slug, stage: 'Closed').all
      open_deals = App::Models::Deal.where(agent_slug: slug).exclude(stage: 'Closed').all
      leads_count = App::Models::Lead.where(agent_slug: slug).count
      deals_count = closed_deals.size
      total_revenue = closed_deals.sum { |d| d.value || 0 }
      rate = commission_rate.to_f

      deal_commission = ->(d) { d.agent_commission_amount || ((d.value.to_i * rate) / 100.0).round }
      pending_commission = open_deals.sum { |d| (d.value.to_i * rate / 100.0).round }

      monthly = closed_deals
        .group_by { |d| (d.closing_date || d.created_at).strftime('%b %Y') }
        .sort_by { |_, deals| deals.map { |d| d.closing_date || d.created_at }.min }
        .map { |month, deals| { 'month' => month, 'earned' => deals.sum { |d| deal_commission.call(d) } } }

      approved_reviews = App::Models::Review.where(reviewable_type: 'Agent', reviewable_id: id, status: 'Approved').all
      avg_rating = approved_reviews.empty? ? 0 : (approved_reviews.sum(&:stars).to_f / approved_reviews.size).round(1)

      {
        'leads_assigned' => leads_count,
        'bookings' => deals_count,
        'deals_closed' => deals_count,
        'revenue' => total_revenue,
        'rating' => avg_rating,
        'pending_commission' => pending_commission,
        'conversion_rate' => leads_count.zero? ? 0 : ((deals_count / leads_count.to_f) * 100).round(1),
        'commission_earned' => closed_deals.sum { |d| deal_commission.call(d) },
        'commission_monthly' => monthly,
      }
    end
  end

  # Admin read shape (services/agents.rb#list/#get/#update/#create) — to_pos
  # plus the live-computed fields above, same "to_pos.merge(...)" shape as
  # FollowUp#with_overdue. `age` is merged in explicitly since it's a plain
  # Ruby method now (derived from date_of_birth, migrations/0086), not a
  # column — as_json/to_pos only serializes real columns on its own.
  def with_live_stats
    to_pos.merge(live_stats).merge('age' => age)
  end

  # Doubles as "activate my account" for a legacy agent who predates
  # services/agents.rb#create's temp-password flow below and so still has
  # no password at all (encoded_password nil).
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

  # Admin-created account's first password (services/agents.rb#create) —
  # same exact `mail` gem/SMTP infra and "email it instead of showing it in
  # the admin UI" reasoning as RamMember#send_temporary_password_email/
  # Client#send_temporary_password_email. The agent changes it afterward via
  # the Agent Portal's own existing update-password flow
  # (AgentAuth#update_password), which also clears must_change_password.
  def send_temporary_password_email(temp_password)
    agent_email = self.email
    agent_name = self.name

    mail = Mail.new do
      from    'apps@srinishtha.com'
      to      agent_email
      subject 'Your REROCK Realty agent portal login'
      html_part do
        content_type 'text/html; charset=UTF-8'
        body <<-HTML
          <html>
          <body>
            <h1>Welcome to REROCK Realty</h1>
            <p>Hello #{agent_name},</p>
            <p>An account has been created for you on the REROCK Realty Agent Portal. Here is your temporary password:</p>
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

  # Shaped to match the Agent Portal's existing camelCase mock shape
  # (lib/data/agents.js) every portal page/component was written against —
  # same "shape the response to match what the existing frontend already
  # expects" convention as User#as_pos/RamMember#as_pos/Client#as_pos. Never
  # includes encoded_password/current_session_id/reset_token/otp_code.
  def as_pos
    stats = live_stats
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
      'profession' => profession,
      'dateOfBirth' => date_of_birth,
      'age' => age,
      'dealsClosed' => stats['deals_closed'],
      'rating' => stats['rating'],
      'experienceYears' => experience_years,
      'strongAreas' => strong_area_ids,
      'address' => address,
      'status' => status,
      'territory' => territory,
      'bookings' => stats['bookings'],
      'revenue' => stats['revenue'],
      'conversionRate' => stats['conversion_rate'],
      'commissionRate' => commission_rate,
      'commissionEarned' => stats['commission_earned'],
      'pendingCommission' => stats['pending_commission'],
      'leadsAssigned' => stats['leads_assigned'],
      'joinedDate' => joined_date,
      'commissionMonthly' => stats['commission_monthly'],
      'tasks' => tasks,
      'attendance' => attendance,
      'propertiesSold' => properties_sold,
      'propertiesAssigned' => properties_assigned,
      'documents' => documents,
      'activityLog' => activity_log,
      'hasPassword' => !encoded_password.nil?,
      'mustChangePassword' => must_change_password,
    }
  end
end
