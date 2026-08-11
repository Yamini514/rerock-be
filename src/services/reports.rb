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
end
