class App::Services::Clients < App::Services::Base
  def model; Client; end

  # Mirrors lib/data/clients.js: search by name/email/phone, plus exact
  # filters for status/type/referred_by_id (the latter used by the detail
  # page's "Referred Clients" tab, replacing the mock's referralsFor(id)).
  def list
    ds = model.order(Sequel.desc(:created_at))
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
    return_success(ds.all.map(&:to_pos))
  end

  # Same as Base#update, but also lets the client know their own profile
  # changed — the only difference from the inherited version is the
  # Notification.create after a successful save.
  def update(data=nil)
    data ||= data_for(:save)
    item.set_fields(data, data.keys)
    save(item) do |obj|
      Notification.create(
        audience: "client",
        recipient_id: obj.id,
        type: "profile",
        icon: "UserCog",
        title: "Your profile was updated",
        message: "Your account details were updated by our team."
      )
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
        :invested_properties, :notes, :communication_log, :timeline
      ]
    }
  end
end
