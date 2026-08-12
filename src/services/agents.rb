class App::Services::Agents < App::Services::Base
  def model; Agent; end

  # Mirrors lib/data/agents.js: search by name/email, plus exact filters for
  # status/territory.
  #
  # bookings/revenue/conversion_rate/leads_assigned/deals_closed are
  # deliberately NOT in SORTABLE_COLUMNS — Agent#with_live_stats (below)
  # recomputes those live from Deal/Lead on every read, overriding whatever
  # stale value sits in the `agents` table's own same-named columns. Sorting
  # by the stored column would silently disagree with the value actually
  # shown in the UI.
  SORTABLE_COLUMNS = %w[name territory rating status created_at].freeze

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

  # See Base#create — overridden only to swap the plain to_pos for
  # with_live_stats, same reason as #list/#get above (a brand-new agent's
  # live stats are all zero anyway, kept only for response-shape
  # consistency with #list/#get/#update).
  def create
    obj = model.new(data_for(:save))
    save(obj) { |o| return_success(o.with_live_stats) }
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
  # commission_monthly are deliberately NOT in this whitelist anymore —
  # they're computed live on every read now (Agent#live_stats), so an admin
  # PUT can no longer write a value that would just be overwritten by the
  # next read anyway. commission_rate/commission_earned/pending_commission
  # stay admin-set (see Agent#live_stats's own comment on why those three
  # aren't derived yet).
  def self.fields
    {
      save: [
        :slug, :name, :role, :email, :phone, :whatsapp, :avatar,
        :specialization, :rating, :experience_years,
        :strong_area_ids, :address, :status, :territory,
        :commission_rate, :commission_earned, :pending_commission, :joined_date,
        :tasks, :attendance,
        :properties_sold, :properties_assigned, :documents, :activity_log
      ]
    }
  end
end
