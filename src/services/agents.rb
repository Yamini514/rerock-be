class App::Services::Agents < App::Services::Base
  def model; Agent; end

  # Mirrors lib/data/agents.js: search by name/email, plus exact filters for
  # status/territory.
  #
  # bookings/revenue/conversion_rate/leads_assigned/deals_closed/rating are
  # deliberately NOT in SORTABLE_COLUMNS — Agent#with_live_stats (below)
  # recomputes those live from Deal/Lead/Review on every read, overriding
  # whatever stale value sits in the `agents` table's own same-named
  # columns. Sorting by the stored column would silently disagree with the
  # value actually shown in the UI.
  SORTABLE_COLUMNS = %w[name territory status created_at].freeze

  def list
    ds = model
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    ds = ds.where(territory: qs[:territory]) if qs[:territory].present?
    if qs[:search].present?
      # Same fix as leads.rb/site_visits.rb/referrals.rb/clients.rb:
      # `Dataset#or` ORs the new condition against the dataset's *entire*
      # existing WHERE clause, which would swallow the status/territory
      # filters above whenever a search term is also present. Combine the
      # two LIKEs with `|` first, then AND the combined expression in with
      # `where`.
      term = "%#{qs[:search]}%"
      ds = ds.where(
        Sequel.like(:name, term, case_insensitive: true) | Sequel.like(:email, term, case_insensitive: true)
      )
    end
    ds = apply_sort(ds, SORTABLE_COLUMNS, default: [[:created_at, :desc]])
    paginated_response(ds) { |a| a.with_live_stats }
  end

  # See Base#get — overridden only to swap the plain to_pos for
  # with_live_stats (Agent#live_stats), same reason as #list above.
  def get
    return_success(item.with_live_stats)
  end

  # An admin-created agent used to get no password at all (encoded_password
  # stayed nil, forcing a "Forgot password" round-trip just to sign in for
  # the first time) — now generates a real temp password immediately and
  # emails it, same admin-invite pattern as RamMembers#create/
  # RamMember#send_temporary_password_email. `must_change_password` is set
  # so the agent is expected to pick their own real one via the Agent
  # Portal's existing update-password flow (AgentAuth#update_password,
  # which clears the flag). The raw temp_password is also merged into this
  # one response (never returned by #get/#list/#update) so the Admin
  # Portal's Add Agent form can show it once in a confirmation dialog as a
  # fallback alongside the email, in case SMTP isn't reachable in this
  # environment or the admin wants to hand it over directly.
  def create
    obj = model.new(data_for(:save))

    temp_password = SecureRandom.alphanumeric(10)
    obj.password = temp_password
    obj.must_change_password = true

    save(obj) do |o|
      # See Clients#create's identical rescue: the row is already committed
      # by this point, so a slow/failed SMTP send must never turn into a
      # false "agent creation failed" response.
      begin
        o.send_temporary_password_email(temp_password)
      rescue => e
        App.logger.error("[Agents#create] temp password email failed for agent ##{o.id}: #{e.message}")
        App.logger.error(e.backtrace)
      end
      return_success(o.with_live_stats.merge('tempPassword' => temp_password))
    end
  end

  # Status changes (Active/On Leave/Inactive), profile edits, and the
  # remaining jsonb arrays (tasks, attendance, properties_sold,
  # properties_assigned, documents, activity_log) all ride the standard
  # PUT/update below, whitelisted like any other saveable column — the
  # frontend sends each array back whole, already-appended, same convention
  # as Client#notes/#communication_log/Lead#timeline. Overridden (rather
  # than left as Base#update) both to run Agent#notify_of_approval! after a
  # successful save (see that method for why it's safe to call
  # unconditionally on every update) and to return with_live_stats instead
  # of a plain to_pos, same reason as #list/#get above.
  def update(data = nil)
    data ||= data_for(:save)
    item.set_fields(data, data.keys)
    save(item) do |o|
      o.notify_of_approval!
      return_success(o.with_live_stats)
    end
  end

  # bookings/revenue/conversion_rate/leads_assigned/deals_closed/
  # commission_monthly/commission_earned/rating/pending_commission are
  # deliberately NOT in this whitelist — they're computed live on every read
  # now (Agent#live_stats), so an admin PUT can no longer write a value that
  # would just be overwritten by the next read anyway. commission_rate stays
  # admin-set (it's the input to the live commission calc, not an output of
  # it). role/joined_date aren't here either — Agent#before_validation
  # stamps both automatically the moment a record is created and neither is
  # ever editable after. whatsapp/address/strong_area_ids were dropped from
  # the Add/Edit Agent form (simplified to name/email/phone/territory/
  # specialization/experience/commission rate only) and have no other write
  # path, so they're dropped from here too — existing values on legacy
  # agents still read fine via to_pos, just can't be set/changed anymore.
  def self.fields
    {
      save: [
        :slug, :name, :email, :phone, :avatar,
        :specialization, :experience_years, :profession, :date_of_birth,
        :status, :territory, :commission_rate,
        :tasks, :attendance,
        :properties_sold, :properties_assigned, :documents, :activity_log
      ]
    }
  end
end
