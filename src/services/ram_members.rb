class App::Services::RamMembers < App::Services::Base
  def model; RamMember; end

  # Mirrors lib/data/staff.js's ramTeam: search by name/email, plus exact
  # filters for status/region.
  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    ds = ds.where(region: qs[:region]) if qs[:region].present?
    if qs[:search].present?
      # Same fix as agents.rb/leads.rb/clients.rb/etc.: `Dataset#or` ORs the
      # new condition against the dataset's *entire* existing WHERE clause,
      # which would swallow the status/region filters above whenever a search
      # term is also present. Combine the two LIKEs with `|` first, then AND
      # the combined expression in with `where`.
      term = "%#{qs[:search]}%"
      ds = ds.where(
        Sequel.like(:name, term, case_insensitive: true) | Sequel.like(:email, term, case_insensitive: true)
      )
    end
    return_success(ds.all.map(&:to_pos))
  end

  # Status changes (Active/Pending/Inactive, including the "Approve" row
  # action), profile edits, and every jsonb array (recommendations, reports,
  # performance, activities, documents) all ride the standard PUT/update
  # below, whitelisted like any other saveable column — frontend sends each
  # array back whole, already-appended, same convention as Agent#tasks/
  # #activity_log.
  def self.fields
    {
      save: [
        :slug, :name, :email, :avatar, :designation, :builder_ids, :region,
        :deals_this_quarter, :status, :satisfaction, :renewal_rate,
        :avg_response_time_hours, :experience_years, :revenue_managed,
        :conversion_rate_pct, :referral_generated,
        :recommendations, :reports, :performance, :activities, :documents
      ]
    }
  end
end
