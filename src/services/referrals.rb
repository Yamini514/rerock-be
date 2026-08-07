class App::Services::Referrals < App::Services::Base
  def model; Referral; end

  # Mirrors lib/data/referrals.js: search by referrer/referred name, plus
  # exact filters for type/status, ordered newest-first (no curated
  # display_order here either, same as Leads/SiteVisits).
  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(archived: qs[:archived].to_s == 'true') if qs.key?(:archived)
    ds = ds.where(ram_id: qs[:ram_id]) if qs[:ram_id].present?
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

    if qs.key?(:page)
      total = ds.count
      return_success(ds.limit(limit).offset(offset).all.map(&:to_pos), meta: { total: total, page: (qs[:page] || 1).to_i, page_size: page_size })
    else
      return_success(ds.all.map(&:to_pos))
    end
  end

  # Status transitions and reward/date edits all ride the standard
  # PUT/update below — every field is just whitelisted like any other
  # saveable column. `ram_id` filter above added for the RAM Portal's own
  # scoped `my_referrals` (services/ram_portal.rb).
  def self.fields
    {
      save: [
        :ram_id, :type, :referrer, :referred, :status, :reward, :date, :payout_status, :archived
      ]
    }
  end
end
