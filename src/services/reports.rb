class App::Services::Reports < App::Services::Base
  # No single backing table — this service only ever aggregates other
  # services' real tables (Agents/Deals), so `model` is left undefined; both
  # actions below build their own dataset instead of using Base#list/#get.

  # Commission — computed report, no dedicated table. One row per agent,
  # straight from the real `agents` table's own performance columns — same
  # shape lib/data/finance.js's getCommissionRows()/getCommissionSummary()
  # produced over the mock (agents.js), just read from the real Agent model
  # instead of a mock array. Everything is nested under `data` (rather than
  # returned as sibling `return_success` extras) since the frontend's
  # apiRequest wrapper only ever unwraps the response envelope's `data` key.
  def commission
    rows = Agent.order(Sequel.desc(:revenue)).all.map do |a|
      {
        id: a.id,
        agent_slug: a.slug,
        agent_name: a.name,
        territory: a.territory,
        bookings: a.bookings,
        revenue: a.revenue,
        commission_rate: a.commission_rate,
        commission_earned: a.commission_earned,
        pending_commission: a.pending_commission
      }
    end

    summary = {
      total_agents: rows.size,
      total_commission_payable: rows.sum { |r| r[:commission_earned] || 0 },
      total_pending: rows.sum { |r| r[:pending_commission] || 0 },
      avg_commission_rate: rows.empty? ? 0 : (rows.sum { |r| r[:commission_rate] || 0 } / rows.size.to_f).round(2)
    }

    return_success(rows: rows, summary: summary)
  end

  # Revenue — by-agent breakdown (real agents.revenue/bookings), plus a
  # monthly trend approximated from each agent's own commission_monthly jsonb
  # series. DESIGN CALL: kept the mock's own back-calculation
  # (impliedRevenue = earned / commission_rate * 100) rather than dropping
  # the trend entirely — Agent really does carry a commission_monthly jsonb
  # column ({month, earned}[], migrations/0019), so this is the exact same
  # computed derivation the mock used (lib/data/finance.js's
  # getRevenueMonthlyTrend), just run over real rows instead of the mock
  # array. It's still an approximation (no real per-month revenue figure is
  # stored anywhere), which is why it's documented here rather than silently
  # presented as exact.
  def revenue
    agents = Agent.order(Sequel.desc(:revenue)).all

    by_agent = agents.map do |a|
      { id: a.id, agent_name: a.name, territory: a.territory, bookings: a.bookings, revenue: a.revenue }
    end

    months = {}
    agents.each do |a|
      rate = a.commission_rate.to_f
      rate = 1.5 if rate.zero?
      (a.commission_monthly || []).each do |m|
        label = m['month']
        earned = m['earned'].to_f
        next unless label
        implied_revenue = ((earned / rate) * 100).round
        months[label] = (months[label] || 0) + implied_revenue
      end
    end
    trend = months.map { |label, value| { label: label, value: value } }

    total_revenue = agents.sum { |a| a.revenue || 0 }
    total_bookings = agents.sum { |a| a.bookings || 0 }
    summary = {
      total_revenue: total_revenue,
      total_bookings: total_bookings,
      avg_per_booking: total_bookings.zero? ? 0 : (total_revenue / total_bookings.to_f).round,
      active_agents: agents.count { |a| a.status == 'Active' }
    }

    return_success(by_agent: by_agent, trend: trend, summary: summary)
  end
end
