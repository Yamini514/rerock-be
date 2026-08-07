class App::Services::SiteVisits < App::Services::Base
  def model; SiteVisit; end

  # Mirrors lib/data/siteVisits.js: filter by status/date-range/lead/property
  # (plus community_id, same FK-filter convention as leads.rb), search by
  # client name, ordered newest-first (no curated display_order here either).
  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(archived: qs[:archived].to_s == 'true') if qs.key?(:archived)
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    ds = ds.where(lead_id: qs[:lead_id]) if qs[:lead_id].present?
    ds = ds.where(property_id: qs[:property_id]) if qs[:property_id].present?
    ds = ds.where(community_id: qs[:community_id]) if qs[:community_id].present?
    ds = ds.where { date >= qs[:date_from] } if qs[:date_from].present?
    ds = ds.where { date <= qs[:date_to] } if qs[:date_to].present?
    if qs[:search].present?
      # NOTE: same fix as leads.rb — `Dataset#or` ORs the new condition
      # against the dataset's *entire* existing WHERE clause, which would
      # swallow the status/date-range/lead/property/community filters above
      # whenever a search term is also present. There's only a single search
      # field here (client_name), so no `|` combination is even needed — just
      # a plain `where` chained onto the existing dataset, same as every other
      # exact filter above.
      term = "%#{qs[:search]}%"
      ds = ds.where(Sequel.like(:client_name, term, case_insensitive: true))
    end

    if qs.key?(:page)
      total = ds.count
      return_success(ds.limit(limit).offset(offset).all.map(&:to_pos), meta: { total: total, page: (qs[:page] || 1).to_i, page_size: page_size })
    else
      return_success(ds.all.map(&:to_pos))
    end
  end

  # Status transitions (Scheduled -> Completed/Cancelled/Rescheduled) and
  # notes/date/time edits all ride the standard PUT/update below — every
  # field is just whitelisted like any other saveable field.
  def self.fields
    {
      save: [
        :lead_id, :property_id, :community_id, :client_name, :agent_slug,
        :date, :time, :status, :notes, :archived
      ]
    }
  end
end
