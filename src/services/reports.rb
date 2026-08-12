class App::Services::Reports < App::Services::Base
  # No single backing table — this service only ever aggregates other
  # services' real tables (Agents/Deals), so `model` is left undefined; both
  # actions below build their own dataset instead of using Base#list/#get.

  # Commission — computed report, no dedicated table. One row per agent,
  # same shape lib/data/finance.js's getCommissionRows()/getCommissionSummary()
  # produced over the mock (agents.js), just read from the real Agent model
  # instead of a mock array. bookings/revenue come from Agent#live_stats now
  # (computed from real Leads/Deals) rather than the stored columns, so
  # sorting by revenue has to happen in Ruby after computing it — a stored-
  # column `ORDER BY` can no longer do it. Everything is nested under `data`
  # (rather than returned as sibling `return_success` extras) since the
  # frontend's apiRequest wrapper only ever unwraps the response envelope's
  # `data` key.
  def commission
    rows = Agent.all.map do |a|
      stats = a.live_stats
      {
        id: a.id,
        agent_slug: a.slug,
        agent_name: a.name,
        territory: a.territory,
        bookings: stats['bookings'],
        revenue: stats['revenue'],
        commission_rate: a.commission_rate,
        commission_earned: a.commission_earned,
        pending_commission: a.pending_commission
      }
    end.sort_by { |r| -r[:revenue] }

    summary = {
      total_agents: rows.size,
      total_commission_payable: rows.sum { |r| r[:commission_earned] || 0 },
      total_pending: rows.sum { |r| r[:pending_commission] || 0 },
      avg_commission_rate: rows.empty? ? 0 : (rows.sum { |r| r[:commission_rate] || 0 } / rows.size.to_f).round(2)
    }

    return_success(rows: rows, summary: summary)
  end

  # Revenue — by-agent breakdown, plus a monthly trend approximated from each
  # agent's own commission_monthly. bookings/revenue/commission_monthly all
  # come from Agent#live_stats now (computed from real Leads/Deals) rather
  # than the stored columns — same reason #commission above sorts in Ruby
  # instead of `ORDER BY revenue`. DESIGN CALL: kept the mock's own
  # back-calculation (impliedRevenue = earned / commission_rate * 100)
  # rather than dropping the trend entirely — this is the exact same
  # computed derivation the mock used (lib/data/finance.js's
  # getRevenueMonthlyTrend), just run over live-computed rows instead of a
  # mock array. It's still an approximation (no real per-month revenue
  # figure is stored anywhere), which is why it's documented here rather
  # than silently presented as exact.
  def revenue
    agents = Agent.all
    stats_by_agent = agents.each_with_object({}) { |a, h| h[a.id] = a.live_stats }

    by_agent = agents.map do |a|
      stats = stats_by_agent[a.id]
      { id: a.id, agent_name: a.name, territory: a.territory, bookings: stats['bookings'], revenue: stats['revenue'] }
    end.sort_by { |r| -r[:revenue] }

    months = {}
    agents.each do |a|
      rate = a.commission_rate.to_f
      rate = 1.5 if rate.zero?
      (stats_by_agent[a.id]['commission_monthly'] || []).each do |m|
        label = m['month']
        earned = m['earned'].to_f
        next unless label
        implied_revenue = ((earned / rate) * 100).round
        months[label] = (months[label] || 0) + implied_revenue
      end
    end
    trend = months.map { |label, value| { label: label, value: value } }

    total_revenue = by_agent.sum { |r| r[:revenue] || 0 }
    total_bookings = by_agent.sum { |r| r[:bookings] || 0 }
    summary = {
      total_revenue: total_revenue,
      total_bookings: total_bookings,
      avg_per_booking: total_bookings.zero? ? 0 : (total_revenue / total_bookings.to_f).round,
      active_agents: agents.count { |a| a.status == 'Active' }
    }

    return_success(by_agent: by_agent, trend: trend, summary: summary)
  end

  # Leads — computed report, no dedicated table beyond the real Leads table
  # itself. `status`/`source` are plain strings with no DB-level enum
  # (migrations/0014's own comment), so both breakdowns group whatever
  # values actually exist in the data rather than a hardcoded list — same
  # "aggregate real rows, don't assume a fixed taxonomy" convention as
  # #commission/#revenue above assuming a fixed Agent roster.
  def leads
    all_leads = Lead.all

    by_status = all_leads.group_by { |l| l.status.presence || 'Unknown' }
      .map { |status, rows| { label: status, value: rows.size } }
      .sort_by { |r| -r[:value] }

    by_source = all_leads.group_by { |l| l.source.presence || 'Unknown' }
      .map { |source, rows| { label: source, value: rows.size } }
      .sort_by { |r| -r[:value] }

    by_agent = all_leads.select { |l| l.agent_slug.present? }.group_by(&:agent_slug)
      .map do |slug, rows|
        agent = Agent.where(slug: slug).first
        won = rows.count { |l| l.status == 'Won' }
        lost = rows.count { |l| l.status == 'Lost' }
        {
          id: agent&.id,
          agent_slug: slug,
          agent_name: agent&.name || slug,
          leads_handled: rows.size,
          won: won,
          lost: lost,
          conversion_rate: rows.empty? ? 0 : ((won / rows.size.to_f) * 100).round(1)
        }
      end.sort_by { |r| -r[:leads_handled] }

    total = all_leads.size
    won_total = all_leads.count { |l| l.status == 'Won' }
    lost_total = all_leads.count { |l| l.status == 'Lost' }
    summary = {
      total_leads: total,
      won: won_total,
      lost: lost_total,
      conversion_rate: total.zero? ? 0 : ((won_total / total.to_f) * 100).round(1)
    }

    return_success(by_status: by_status, by_source: by_source, by_agent: by_agent, summary: summary)
  end

  # Site Visits — computed report, no dedicated table beyond the real
  # SiteVisits table itself. `status` is a plain string with an app-level
  # allowed list (Scheduled/Completed/Cancelled/Rescheduled — see
  # migrations/0015's own comment), same "aggregate real rows" convention as
  # #leads above. by_property resolves each visit's real `property`
  # association for a display name — same pattern #commission uses for
  # agent_name via the Agent association.
  def site_visits
    all_visits = SiteVisit.all

    by_status = all_visits.group_by { |v| v.status.presence || 'Unknown' }
      .map { |status, rows| { label: status, value: rows.size } }
      .sort_by { |r| -r[:value] }

    by_agent = all_visits.select { |v| v.agent_slug.present? }.group_by(&:agent_slug)
      .map do |slug, rows|
        agent = Agent.where(slug: slug).first
        completed = rows.count { |v| v.status == 'Completed' }
        {
          id: agent&.id,
          agent_slug: slug,
          agent_name: agent&.name || slug,
          visits: rows.size,
          completed: completed,
          completion_rate: rows.empty? ? 0 : ((completed / rows.size.to_f) * 100).round(1)
        }
      end.sort_by { |r| -r[:visits] }

    by_property = all_visits.select { |v| v.property_id }.group_by(&:property_id)
      .map do |pid, rows|
        completed = rows.count { |v| v.status == 'Completed' }
        {
          id: pid,
          label: rows.first.property&.title || "Property ##{pid}",
          value: rows.size,
          completed: completed,
          completion_rate: rows.empty? ? 0 : ((completed / rows.size.to_f) * 100).round(1)
        }
      end.sort_by { |r| -r[:value] }

    total = all_visits.size
    completed_total = all_visits.count { |v| v.status == 'Completed' }
    cancelled_total = all_visits.count { |v| v.status == 'Cancelled' }
    summary = {
      total_visits: total,
      completed: completed_total,
      cancelled: cancelled_total,
      completion_rate: total.zero? ? 0 : ((completed_total / total.to_f) * 100).round(1)
    }

    return_success(by_status: by_status, by_agent: by_agent, by_property: by_property, summary: summary)
  end

  # Opportunity -> Proposal -> Negotiation -> Booking -> Closed, same order
  # as DEAL_STAGES in the frontend's lib/data/deals.js and migrations/0018's
  # own comment. Returned in this fixed pipeline order (zero-filled) rather
  # than sorted by count, since the stage breakdown is meant to read as a
  # funnel, not a ranking.
  DEAL_STAGE_ORDER = ['Opportunity', 'Proposal', 'Negotiation', 'Booking', 'Closed'].freeze

  # Deals / Sales — computed report, no dedicated table beyond the real
  # Deals table itself. "Closed" is the only stage counted as a successful/
  # booked deal for avg deal value and the by-property breakdown — same
  # convention Agent#live_stats already uses (`Deal.where(stage: 'Closed')`)
  # for a single agent.
  def deals
    all_deals = Deal.all
    closed_deals = all_deals.select { |d| d.stage == 'Closed' }

    by_stage = DEAL_STAGE_ORDER.map { |stage| { label: stage, value: all_deals.count { |d| d.stage == stage } } }

    # Groups by the real property_id when a deal has one, falling back to the
    # free-text property_name otherwise — most deals in practice only carry
    # the fallback string (e.g. every seeded deal has property_id: nil, per
    # Deal's own "real FK + fallback string" comment in migrations/0018), so
    # grouping on property_id alone would silently drop them all.
    by_property = closed_deals.select { |d| d.property_id.present? || d.property_name.present? }
      .group_by { |d| d.property_id || d.property_name }
      .map do |_key, rows|
        {
          id: rows.first.property_id,
          label: rows.first.property&.title || rows.first.property_name,
          value: rows.size,
          total_value: rows.sum { |d| d.value.to_i }
        }
      end.sort_by { |r| -r[:value] }

    total_closed_value = closed_deals.sum { |d| d.value.to_i }
    summary = {
      total_deals: all_deals.size,
      closed_deals: closed_deals.size,
      total_closed_value: total_closed_value,
      avg_deal_value: closed_deals.empty? ? 0 : (total_closed_value / closed_deals.size.to_f).round
    }

    return_success(by_stage: by_stage, by_property: by_property, summary: summary)
  end

  # Clients — computed report, no dedicated table beyond the real Clients
  # table itself. Monthly grouping reuses the same `(joined || created_at)`
  # fallback / `%b %Y` formatting convention as #deals' monthly grouping,
  # since `joined` defaults to the row's creation date but stays a plain
  # editable column (migrations/0017) that could in principle be blank on
  # an old row. `assigned_agent_slug` is a plain nullable string, not a real
  # FK (Client's own validate method just checks it matches a real Agent
  # slug when present) — same "aggregate real rows, resolve the display
  # name via a lookup" convention as #leads' by_agent above.
  #
  # by_ram is intentionally NOT Client#assigned_ram_id (that's "who currently
  # manages this client," unrelated to how the relationship started) — it's
  # built from the real Referral table instead, since "referred people who
  # purchased" is a genuinely different, separately-tracked concept:
  # Referral#status hits 'Purchase Completed' only when a referred lead/
  # client actually buys (see Referral#notify_ram_of_status!), independent
  # of who that client's assigned RAM/agent ends up being.
  def clients
    all_clients = Client.all

    by_month = all_clients
      .group_by { |c| (c.joined || c.created_at).strftime('%b %Y') }
      .sort_by { |_, rows| rows.map { |c| c.joined || c.created_at }.min }
      .map { |month, rows| { label: month, value: rows.size } }

    by_agent = all_clients.select { |c| c.assigned_agent_slug.present? }.group_by(&:assigned_agent_slug)
      .map do |slug, rows|
        agent = Agent.where(slug: slug).first
        { id: agent&.id, agent_slug: slug, agent_name: agent&.name || slug, clients: rows.size }
      end.sort_by { |r| -r[:clients] }

    by_ram = Referral.all.select { |ref| ref.ram_id.present? }.group_by(&:ram_id)
      .map do |slug, rows|
        ram = RamMember.where(slug: slug).first
        purchases = rows.count { |ref| ref.status == 'Purchase Completed' }
        {
          id: ram&.id,
          ram_slug: slug,
          ram_name: ram&.name || slug,
          referrals: rows.size,
          purchases: purchases,
          conversion_rate: rows.empty? ? 0 : ((purchases / rows.size.to_f) * 100).round(1)
        }
      end.sort_by { |r| -r[:purchases] }

    summary = {
      total_clients: all_clients.size,
      active_clients: all_clients.count { |c| c.status == 'Active' },
      assigned_to_agent: all_clients.count { |c| c.assigned_agent_slug.present? },
      assigned_to_ram: all_clients.count { |c| c.assigned_ram_id.present? }
    }

    return_success(by_month: by_month, by_agent: by_agent, by_ram: by_ram, summary: summary)
  end

  # Agent Performance — every agent side by side, one row each. Every figure
  # comes straight from Agent#live_stats (the same computed-from-real-Leads/
  # Deals method #commission above already relies on), so this is really
  # just #commission's own `rows` shape widened to the performance figures
  # (leads/bookings/deals/conversion) instead of the commission figures —
  # no new computation, just a different projection of the same per-agent
  # stats.
  def agent_performance
    rows = Agent.all.map do |a|
      stats = a.live_stats
      {
        id: a.id,
        agent_slug: a.slug,
        agent_name: a.name,
        territory: a.territory,
        status: a.status,
        leads_assigned: stats['leads_assigned'],
        bookings: stats['bookings'],
        deals_closed: stats['deals_closed'],
        revenue: stats['revenue'],
        conversion_rate: stats['conversion_rate']
      }
    end.sort_by { |r| -r[:revenue] }

    summary = {
      total_agents: rows.size,
      total_leads: rows.sum { |r| r[:leads_assigned] || 0 },
      total_deals_closed: rows.sum { |r| r[:deals_closed] || 0 },
      total_revenue: rows.sum { |r| r[:revenue] || 0 },
      avg_conversion_rate: rows.empty? ? 0 : (rows.sum { |r| r[:conversion_rate] || 0 } / rows.size.to_f).round(1)
    }

    return_success(rows: rows, summary: summary)
  end

  # Same fixed enums the Properties/Communities admin forms themselves write
  # from (PROPERTY_STATUSES/COMMUNITY_STATUSES in the frontend's
  # PropertyForm.js/CommunityForm.js) — returned zero-filled in this order so
  # the by-status breakdown reads consistently even when a status has no
  # rows yet.
  PROPERTY_STATUS_ORDER = ['Available', 'Reserved', 'Sold', 'Under Construction', 'Ready To Move'].freeze
  COMMUNITY_STATUS_ORDER = ['RERA Approved', 'Under Construction', 'Ready To Move'].freeze

  # Property / Community Inventory — computed report, no dedicated table.
  # Archived rows are excluded throughout, same "active only" convention the
  # Admin Dashboard's own KPI/status widgets already use.
  def inventory
    all_properties = Property.where(archived: false).all
    all_communities = Community.where(archived: false).all

    property_by_status = PROPERTY_STATUS_ORDER.map { |s| { label: s, value: all_properties.count { |p| p.status == s } } }
    community_by_status = COMMUNITY_STATUS_ORDER.map { |s| { label: s, value: all_communities.count { |c| c.status == s } } }

    total_units = all_communities.sum { |c| c.total_units.to_i }
    available_units = all_communities.sum { |c| c.available_units.to_i }
    booked_units = total_units - available_units

    summary = {
      total_properties: all_properties.size,
      available_properties: all_properties.count { |p| p.status == 'Available' },
      sold_properties: all_properties.count { |p| p.status == 'Sold' },
      total_units: total_units,
      available_units: available_units,
      booked_units: booked_units
    }

    return_success(
      property_by_status: property_by_status,
      community_by_status: community_by_status,
      summary: summary
    )
  end

  # CRM Activity — computed report, no dedicated table.
  #
  # Completed/overdue reuses FollowUp#with_overdue exactly as-is (the same
  # "done vs due_date < today" flag services/follow_ups.rb#list and
  # services/agent_portal.rb#my_follow_ups already compute) instead of
  # re-deriving the done/overdue boolean logic here.
  #
  # Enquiry trend is just Lead#created_at grouped by month — every lead has
  # one (it's the row's own creation date, not an optional field like
  # Deal#closing_date), so no fallback needed here unlike #deals/#clients.
  #
  # Communication/call activity has no dedicated table: it's the real,
  # admin-logged `Client#communication_log` jsonb array (one entry per
  # logged call/WhatsApp/email/meeting, written from the Client Detail
  # page's own "Log Communication" form — see ClientDetailClient.js's
  # submitComm) flattened across every client and grouped by its `type`
  # field. FollowUp (scheduled reminders/tasks) is a distinct concept from
  # this (actual logged interactions), so it isn't reused here.
  def crm_activity
    all_follow_ups = FollowUp.all.map(&:with_overdue)
    completed_follow_ups = all_follow_ups.count { |f| f['done'] }
    overdue_follow_ups = all_follow_ups.count { |f| f['overdue'] }
    pending_follow_ups = all_follow_ups.size - completed_follow_ups - overdue_follow_ups

    follow_up_status = [
      { label: 'Completed', value: completed_follow_ups },
      { label: 'Overdue', value: overdue_follow_ups },
      { label: 'Pending', value: pending_follow_ups }
    ]

    enquiry_trend = Lead.all
      .group_by { |l| l.created_at.strftime('%b %Y') }
      .sort_by { |_, rows| rows.map(&:created_at).min }
      .map { |month, rows| { label: month, value: rows.size } }

    all_comm_entries = Client.all.flat_map { |c| Array(c.communication_log) }
    comm_by_type = all_comm_entries
      .group_by { |e| e['type'].presence || 'Unknown' }
      .map { |type, rows| { label: type, value: rows.size } }
      .sort_by { |r| -r[:value] }

    summary = {
      total_follow_ups: all_follow_ups.size,
      completed_follow_ups: completed_follow_ups,
      overdue_follow_ups: overdue_follow_ups,
      total_communications: all_comm_entries.size
    }

    return_success(follow_up_status: follow_up_status, enquiry_trend: enquiry_trend, comm_by_type: comm_by_type, summary: summary)
  end
end
