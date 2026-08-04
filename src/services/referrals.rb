class App::Services::Referrals < App::Services::Base
  def model; Referral; end

  # Mirrors lib/data/referrals.js: search by referrer/referred name, plus
  # exact filters for type/status, ordered newest-first (no curated
  # display_order here either, same as Leads/SiteVisits).
  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(type: qs[:type]) if qs[:type].present?
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    if qs[:search].present?
      # NOTE: same fix as leads.rb/site_visits.rb — `Dataset#or` ORs the new
      # condition against the dataset's *entire* existing WHERE clause, which
      # would swallow the type/status filters above whenever a search term is
      # also present. Combining the two LIKEs with `|` first, then ANDing the
      # combined expression in with `where`, keeps the other filters intact.
      term = "%#{qs[:search]}%"
      ds = ds.where(
        Sequel.like(:referrer, term, case_insensitive: true) | Sequel.like(:referred, term, case_insensitive: true)
      )
    end
    return_success(ds.all.map(&:to_pos))
  end

  # Status transitions and reward/date edits all ride the standard
  # PUT/update below — every field is just whitelisted like any other
  # saveable column.
  def self.fields
    {
      save: [
        :ram_id, :type, :referrer, :referred, :status, :reward, :date
      ]
    }
  end
end
