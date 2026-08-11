class App::Services::Clients < App::Services::Base
  def model; Client; end

  # Mirrors lib/data/clients.js: search by name/email/phone, plus exact
  # filters for status/type/referred_by_id (the latter used by the detail
  # page's "Referred Clients" tab, replacing the mock's referralsFor(id)).
  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(archived: qs[:archived].to_s == 'true') if qs.key?(:archived)
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    ds = ds.where(type: qs[:type]) if qs[:type].present?
    ds = ds.where(referred_by_id: qs[:referred_by_id]) if qs[:referred_by_id].present?
    if qs[:search].present?
      # Same fix as leads.rb/site_visits.rb/referrals.rb: `Dataset#or` ORs the
      # new condition against the dataset's *entire* existing WHERE clause,
      # which would swallow the status/type/referred_by_id filters above
      # whenever a search term is also present. Combine the three LIKEs with
      # `|` first, then AND the combined expression in with `where`.
      term = "%#{qs[:search]}%"
      ds = ds.where(
        Sequel.like(:name, term, case_insensitive: true) |
        Sequel.like(:email, term, case_insensitive: true) |
        Sequel.like(:phone, term, case_insensitive: true)
      )
    end

    if qs.key?(:page)
      total = ds.count
      return_success(ds.limit(limit).offset(offset).all.map(&:to_pos), meta: { total: total, page: (qs[:page] || 1).to_i, page_size: page_size })
    else
      return_success(ds.all.map(&:to_pos))
    end
  end

  # Every admin-created client gets a working client-portal login
  # immediately — a random temporary password (never typed by the admin,
  # never shown in the admin UI) emailed straight to the client
  # (Client#send_temporary_password_email), pre-verified since an
  # admin-provisioned account doesn't need to prove it owns the email
  # address the way a self-registered one does. The client changes it
  # afterward via the portal's own existing self-service Update Password
  # flow — this doesn't need a new reset mechanism of its own.
  def create
    client = Client.new(data_for(:save))
    temp_password = SecureRandom.alphanumeric(10)
    client.password = temp_password
    client.email_verified_at = Time.now
    save(client) do |obj|
      obj.send_temporary_password_email(temp_password)
      obj.notify_of_agent_assignment!
      return_success(obj.to_pos)
    end
  end

  # Same as Base#update, but also lets the client know something happened
  # to their own account, and lets the agent know if they're the one newly
  # assigned to this client — the only difference from the inherited
  # version is which Notification(s) fire after a successful save. When
  # this save is specifically an agent (re)assignment, the client gets the
  # more specific "Agent assigned" notice (Client#notify_of_agent_assignment!,
  # which also tells the agent) instead of the generic one — a client
  # doesn't need both messages for the same single edit.
  def update(data=nil)
    data ||= data_for(:save)
    agent_changing = data.key?(:assigned_agent_slug) && data[:assigned_agent_slug] != item.assigned_agent_slug
    item.set_fields(data, data.keys)
    save(item) do |obj|
      if agent_changing
        obj.notify_of_agent_assignment!
      else
        Notification.create(
          audience: "client",
          recipient_id: obj.id,
          type: "profile",
          icon: "UserCog",
          title: "Your profile was updated",
          message: "Your account details were updated by our team."
        )
      end
      return_success(obj.to_pos)
    end
  end

  # Status toggles (Active/Inactive), note/communication-log appends, and
  # invested-property adds/removes all ride the standard PUT/update below —
  # every field whitelisted like any other saveable column. The jsonb arrays
  # (`invested_properties`, `notes`, `communication_log`, `timeline`) are sent
  # back whole on every change, same "no per-entry whitelisting, frontend
  # sends the full already-appended array" convention as
  # Community#nearby/Property#floor_plans/Lead#timeline.
  #
  # `properties` (count) and `portfolioValue` are deliberately NOT in this
  # list — both are derived on the frontend from `invested_properties`
  # (length, and sum of currentValue, respectively) rather than stored
  # columns, per the task's own instruction. See migrations/0017 for the
  # same note.
  def self.fields
    {
      save: [
        :name, :email, :phone, :avatar, :joined, :status,
        :assigned_agent_slug, :assigned_ram_id, :type, :city,
        :referral_source, :referred_by_id,
        :invested_properties, :notes, :communication_log, :timeline, :archived
      ]
    }
  end
end
