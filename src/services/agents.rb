class App::Services::Agents < App::Services::Base
  def model; Agent; end

  # Mirrors lib/data/agents.js: search by name/email, plus exact filters for
  # status/territory.
  def list
    ds = model.order(Sequel.desc(:created_at))
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
    return_success(ds.all.map(&:to_pos))
  end

  # Status changes (Active/On Leave/Inactive), profile edits, and every
  # jsonb array (commission_monthly, tasks, attendance, properties_sold,
  # properties_assigned, documents, activity_log) all ride the standard
  # PUT/update below, whitelisted like any other saveable column — the
  # frontend sends each array back whole, already-appended, same convention
  # as Client#notes/#communication_log/Lead#timeline.
  def self.fields
    {
      save: [
        :slug, :name, :role, :email, :phone, :whatsapp, :avatar,
        :specialization, :deals_closed, :rating, :experience_years,
        :strong_area_ids, :address, :status, :territory,
        :bookings, :revenue, :conversion_rate, :commission_rate,
        :commission_earned, :pending_commission, :leads_assigned, :joined_date,
        :commission_monthly, :tasks, :attendance,
        :properties_sold, :properties_assigned, :documents, :activity_log
      ]
    }
  end
end
