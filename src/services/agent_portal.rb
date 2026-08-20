# The Agent Portal's own scoped slice of the CRM — Deals/Leads/SiteVisits
# are all real, already-built Admin Portal resources (services/deals.rb,
# leads.rb, site_visits.rb), and Clients (services/clients.rb) too, but all
# four are admin_required!-gated. An agent's own JWT (CurrentAgent) can't
# satisfy that gate (by design — see helpers/current_agent.rb), so this
# service re-exposes exactly the same tables, filtered server-side to the
# authenticated agent's own agent_slug/assigned_agent_slug on every read,
# with an explicit ownership check on every write. No `model`/generic
# list/get/create/update/delete here — every action is bespoke and scoped,
# unlike a normal do_crud resource service.
#
# This is what makes the Deals Kanban board (frontend's
# components/agent/deals/KanbanBoard.js) — previously 100% local React
# state with zero API calls, flagged in the very first architecture pass as
# "structurally can't reach the real endpoint" — finally reach the real
# `deals` table.
class App::Services::AgentPortal < App::Services::Base
  def current_agent
    CurrentAgent.agent_obj
  end

  def my_deals
    agent = current_agent
    return_errors!("Not signed in.", 401) if agent.nil?

    return_success(Deal.where(agent_slug: agent.slug).order(Sequel.desc(:created_at)).all.map(&:with_status_history))
  end

  # Stage moves (the Kanban board's inline stage Select) plus
  # probability/value/closing-date edits — the same fields Deals#fields
  # allows an admin to touch, minus client_id/client_name/property_id/
  # property_name/agent_slug: an agent moving their own deal through the
  # pipeline shouldn't be reassigning who it belongs to or which
  # client/property it's for from this scoped endpoint.
  def update_my_deal
    agent = current_agent
    return_errors!("Not signed in.", 401) if agent.nil?

    deal = Deal[rp[:id]]
    return_errors!("Deal not found.", 404) if deal.nil?
    return_errors!("This deal isn't assigned to you.", 403) unless deal.agent_slug == agent.slug

    allowed = params.slice(:stage, :probability, :value, :closing_date, :notes)
    stage_changing = allowed.key?(:stage) && allowed[:stage] != deal.stage
    deal.set_fields(allowed, allowed.keys)
    save(deal) do |o|
      o.ensure_commission_for_closure!
      o.ensure_agent_commission_for_closure!
      o.sync_property_status_for_stage!
      o.notify_client_of_closure!
      o.sync_lead_status_for_closure!
      DealStatusHistory.create(deal_id: o.id, status: o.stage, changed_by: agent.name, notes: params[:status_note].presence) if stage_changing
      return_success(o.with_status_history)
    end
  end

  def my_leads
    agent = current_agent
    return_errors!("Not signed in.", 401) if agent.nil?

    return_success(Lead.where(agent_slug: agent.slug).order(Sequel.desc(:created_at)).all.map(&:with_status_history))
  end

  # Stage/priority/follow-up edits and timeline appends — same "whole array
  # back, already-appended" convention as Leads#fields itself, minus the
  # FK-shaped fields (property_id/community_id/area_id/agent_slug/ram_id):
  # reassignment stays an admin action. Also writes a `lead_status_histories`
  # row on a real status change — same pattern as services/leads.rb#update.
  def update_my_lead
    agent = current_agent
    return_errors!("Not signed in.", 401) if agent.nil?

    lead = Lead[rp[:id]]
    return_errors!("Lead not found.", 404) if lead.nil?
    return_errors!("This lead isn't assigned to you.", 403) unless lead.agent_slug == agent.slug

    allowed = params.slice(:status, :priority, :budget, :next_follow_up, :last_follow_up, :timeline)
    status_changing = allowed.key?(:status) && allowed[:status] != lead.status
    lead.set_fields(allowed, allowed.keys)
    save(lead) do |o|
      LeadStatusHistory.create(lead_id: o.id, status: o.status, changed_by: agent.name, notes: params[:status_note].presence) if status_changing
      return_success(o.with_status_history)
    end
  end

  def my_site_visits
    agent = current_agent
    return_errors!("Not signed in.", 401) if agent.nil?

    return_success(SiteVisit.where(agent_slug: agent.slug).order(Sequel.desc(:created_at)).all.map(&:to_pos))
  end

  # Agent-initiated site visit — the frontend's "Schedule Site Visit" flow
  # (Property Detail page's modal, and the Lead Detail page's own header
  # button) both used to fake this client-side with a toast + setTimeout,
  # creating nothing. `agent_slug`/`status` are server-set, never trusted
  # from the client — same "an agent can't reassign who owns this record"
  # reasoning as update_my_deal/update_my_lead/update_my_site_visit above.
  def create_my_site_visit
    agent = current_agent
    return_errors!("Not signed in.", 401) if agent.nil?

    client_name = params[:client_name]&.strip
    return_errors!("Client name is required.", 400) if client_name.blank?
    return_errors!("A visit date is required.", 400) if params[:date].blank?

    date = begin
      Date.parse(params[:date].to_s)
    rescue ArgumentError, TypeError
      nil
    end
    return_errors!("Enter a valid visit date.", 400) if date.nil?
    return_errors!("Visit date can't be in the past.", 400) if date < Date.today

    lead = nil
    if params[:lead_id].present?
      lead = Lead[params[:lead_id]]
      return_errors!("Lead not found.", 404) if lead.nil?
      return_errors!("This lead isn't assigned to you.", 403) unless lead.agent_slug == agent.slug
    end

    property = params[:property_id].present? ? Property[params[:property_id]] : nil

    visit = SiteVisit.new(
      lead_id: lead&.id,
      property_id: params[:property_id].presence,
      community_id: params[:community_id].presence,
      client_name: client_name,
      date: date,
      time: params[:time].presence,
      notes: params[:notes]&.strip.presence,
      agent_slug: agent.slug,
      status: "Scheduled"
    )

    save(visit) do |o|
      Notification.create(
        audience: "admin",
        type: "visit",
        icon: "CalendarCheck",
        title: "New site visit scheduled",
        message: "#{agent.name} scheduled a visit for #{client_name}#{property ? " at #{property.title}" : ""}."
      )

      # Only ever notify a client we've actually verified — never a guess
      # off the free-text client_name above (an agent can type anything
      # there, e.g. scheduling for a walk-in prospect with no account yet).
      # lead.client_id (migrations/0050) is only ever set when that lead was
      # genuinely linked to a real Client account, so this is a real
      # identity match, not a name lookup.
      if lead&.client_id
        Notification.create(
          audience: "client",
          recipient_id: lead.client_id,
          type: "visit",
          icon: "CalendarCheck",
          title: "Site visit scheduled",
          message: "Your advisor #{agent.name} scheduled a site visit#{property ? " for #{property.title}" : ""} on #{date.strftime('%d %b %Y')}."
        )
      end

      return_success(o.to_pos)
    end
  end

  def update_my_site_visit
    agent = current_agent
    return_errors!("Not signed in.", 401) if agent.nil?

    visit = SiteVisit[rp[:id]]
    return_errors!("Site visit not found.", 404) if visit.nil?
    return_errors!("This site visit isn't assigned to you.", 403) unless visit.agent_slug == agent.slug

    allowed = params.slice(:status, :notes, :date, :time)
    visit.set_fields(allowed, allowed.keys)
    save(visit) { |o| o.ensure_deal_for_completion!; o.notify_client_of_status!; return_success(o.to_pos) }
  end

  # Follow Ups (backend/src/services/follow_ups.rb) is a real `agent_id`
  # FK — unlike Deals/Leads/SiteVisits/Clients above, which are all scoped
  # by the deferred `agent_slug` string. Same "not-done first, soonest due
  # date first" order as the admin list, and the same live-computed
  # `overdue` flag (FollowUp#with_overdue) rather than a stored column.
  def my_follow_ups
    agent = current_agent
    return_errors!("Not signed in.", 401) if agent.nil?

    rows = FollowUp.where(agent_id: agent.id, archived: false).order(Sequel.asc(:done), Sequel.asc(:due_date)).all
    return_success(rows.map(&:with_overdue))
  end

  # An agent can mark their own follow-up done, add notes, or nudge its
  # date/type/priority — not reassign who it's for/about (client_name,
  # lead_id, property_id, agent_id all stay admin-only via /admin/follow-ups,
  # same "no reassigning your own book of business" reasoning as
  # update_my_deal/update_my_lead/update_my_site_visit above).
  def update_my_follow_up
    agent = current_agent
    return_errors!("Not signed in.", 401) if agent.nil?

    follow_up = FollowUp[rp[:id]]
    return_errors!("Follow-up not found.", 404) if follow_up.nil?
    return_errors!("This follow-up isn't assigned to you.", 403) unless follow_up.agent_id == agent.id

    allowed = params.slice(:due_date, :type, :priority, :done, :notes)
    follow_up.set_fields(allowed, allowed.keys)
    save(follow_up) { |o| return_success(o.with_overdue) }
  end

  # Read-only: an agent can see their own assigned clients' CRM record, but
  # editing the client relationship itself (notes/communication_log/
  # invested_properties/reassignment) stays an admin/advisor action via
  # /admin/clients, same reasoning as the Client Portal's own
  # ClientAuth#update_profile excluding invested_properties.
  def my_clients
    agent = current_agent
    return_errors!("Not signed in.", 401) if agent.nil?

    return_success(Client.where(assigned_agent_slug: agent.slug).order(Sequel.desc(:created_at)).all.map(&:with_status_history))
  end

  # Status/notes update for the agent's own Leads/Clients/Deals pipeline
  # table (Agent Dashboard) — same "not reassigning who it's for, just moving
  # it through the pipeline" reasoning as update_my_deal/update_my_lead
  # above. `communication_log` is a plain jsonb array, whole-array-back like
  # Lead#timeline (see services/clients.rb's own :communication_log
  # whitelist) — no per-entry validation here either.
  def update_my_client
    agent = current_agent
    return_errors!("Not signed in.", 401) if agent.nil?

    client = Client[rp[:id]]
    return_errors!("Client not found.", 404) if client.nil?
    return_errors!("This client isn't assigned to you.", 403) unless client.assigned_agent_slug == agent.slug

    allowed = params.slice(:status, :communication_log)
    status_changing = allowed.key?(:status) && allowed[:status] != client.status
    client.set_fields(allowed, allowed.keys)
    save(client) do |o|
      ClientStatusHistory.create(client_id: o.id, status: o.status, changed_by: agent.name, notes: params[:status_note].presence) if status_changing
      return_success(o.with_status_history)
    end
  end

  # Documents uploaded by the agent's own assigned clients, awaiting the
  # agent's verification step (see services/client_documents.rb for the
  # upload side, services/approvals.rb for the admin-approval side that
  # follows).
  def my_documents
    agent = current_agent
    return_errors!("Not signed in.", 401) if agent.nil?

    client_ids = Client.where(assigned_agent_slug: agent.slug).select_map(:id)
    return_success(Document.where(client_id: client_ids).order(Sequel.desc(:created_at)).all.map(&:to_pos))
  end

  # Agent's "Verified" step — moves a client's document from Pending to
  # Verified and opens a Pending row in the existing generic Approvals
  # queue (services/approvals.rb) so it surfaces in the admin dashboard's
  # PendingApprovalsWidget without any new admin UI. The admin's own
  # approve/reject on that row is what finally notifies the client (see
  # Approvals#update).
  def verify_my_document
    agent = current_agent
    return_errors!("Not signed in.", 401) if agent.nil?

    document = Document[rp[:id]]
    return_errors!("Document not found.", 404) if document.nil?
    return_errors!("This document isn't from one of your clients.", 403) unless document.client&.assigned_agent_slug == agent.slug
    return_errors!("This document has already been verified.", 400) unless document.status == "Pending"

    allowed = { status: "Verified", verified_by_agent_slug: agent.slug, verified_at: Time.now }
    document.set_fields(allowed, allowed.keys)
    save(document) do |o|
      Approval.create(
        type: "Document",
        title: "Document verification: #{o.name} (#{o.client.name})",
        requested_by: agent.name,
        status: "Pending",
        entity: "Document",
        entity_id: o.id.to_s,
        notes: o.notes
      )
      Notification.create(
        audience: "admin",
        type: "document",
        icon: "FileCheck2",
        title: "Document verified",
        message: "#{agent.name} verified #{o.client.name}'s #{o.category.downcase} \"#{o.name}\" — awaiting your approval."
      )
      return_success(o.to_pos)
    end
  end

  # Backs the Performance page (frontend's app/agent/(portal)/performance).
  # Operational metrics only (Leads, Qualified Leads, Site Visits,
  # Conversions, Deals, Follow-ups, Activities) — finance metrics
  # (sales value, commission, client satisfaction) were dropped per spec.
  #
  # `summary`'s YTD-labeled tiles read from Agent#live_stats plus this
  # agent's own real Leads/SiteVisits/FollowUps — lifetime-to-date totals,
  # not actually reset every Jan 1 (no such column/reset job exists) — same
  # caveat Reports#revenue already documents for its own numbers.
  #
  # `monthly`, by contrast, has no backing column at all — leads/deals/
  # visits-by-month don't exist anywhere, mock or real — so it's computed on
  # the fly from this agent's own Leads/Deals/SiteVisits, grouped by month in
  # Ruby (same "group jsonb/rows in Ruby rather than raw SQL" style
  # Reports#revenue already uses for its commission_monthly trend).
  def my_performance
    agent = current_agent
    return_errors!("Not signed in.", 401) if agent.nil?

    leads = Lead.where(agent_slug: agent.slug).all
    closed_deals = Deal.where(agent_slug: agent.slug, stage: "Closed").all
    visits = SiteVisit.where(agent_slug: agent.slug).all
    follow_ups = FollowUp.where(agent_id: agent.id).all

    leads_by_month = leads.group_by { |l| month_key(l.created_at) }
    deals_by_month = closed_deals.group_by { |d| month_key(d.closing_date || d.created_at) }
    visits_by_month = visits.group_by { |v| month_key(v.date || v.created_at) }
    follow_ups_by_month = follow_ups.group_by { |f| month_key(f.due_date || f.created_at) }

    monthly = last_six_months.map do |m|
      key = m.strftime("%Y-%m")
      month_leads = leads_by_month[key] || []
      month_deals = deals_by_month[key] || []
      month_visits = visits_by_month[key] || []
      month_follow_ups = follow_ups_by_month[key] || []

      leads_count = month_leads.size
      deals_count = month_deals.size

      {
        month: m.strftime("%b"),
        leads_generated: leads_count,
        qualified_leads: month_leads.count { |l| l.status == "Qualified Lead" },
        deals_closed_count: deals_count,
        visits: month_visits.size,
        follow_ups: month_follow_ups.size,
        activities: month_leads.sum { |l| (l.timeline || []).size },
        # Derived, not stored — same "computed from real columns, documented
        # as an approximation" convention as Reports#revenue's implied_revenue.
        conversion_rate: leads_count.zero? ? 0 : ((deals_count / leads_count.to_f) * 100).round(1),
      }
    end

    # Same ranking basis (deals closed, desc) as Reports#commission's
    # admin-wide table — just resolved down to "where does *this* agent
    # land" instead of returning every agent's row, and re-based on a real
    # operational count now that revenue is no longer part of Performance.
    ranked_slugs = Agent.all.sort_by { |a| -a.live_stats['deals_closed'] }.map(&:slug)
    rank = ranked_slugs.index(agent.slug)

    stats = agent.live_stats
    summary = {
      total_leads_ytd: stats['leads_assigned'],
      qualified_leads_ytd: leads.count { |l| l.status == "Qualified Lead" },
      site_visits_ytd: visits.size,
      avg_conversion_rate: stats['conversion_rate'],
      deals_closed_ytd: stats['deals_closed'],
      follow_ups_total: follow_ups.size,
      follow_ups_completed: follow_ups.count(&:done),
      activities_ytd: leads.sum { |l| (l.timeline || []).size },
      monthly_ranking: rank.nil? ? nil : rank + 1,
    }

    return_success(summary: summary, monthly: monthly)
  end

  # Leave requests the agent has submitted for admin review — see
  # services/leave_requests.rb#update for the approve/reject side.
  def my_leave_requests
    agent = current_agent
    return_errors!("Not signed in.", 401) if agent.nil?

    return_success(AgentLeaveRequest.where(agent_id: agent.id).order(Sequel.desc(:created_at)).all.map(&:to_pos))
  end

  # Real leave requests always originate here, never via the admin-facing
  # LeaveRequests#create — `agent_id`/`status` are server-set, never trusted
  # from the client, same "an agent can't reassign who owns this record"
  # reasoning as create_my_site_visit above.
  def create_my_leave_request
    agent = current_agent
    return_errors!("Not signed in.", 401) if agent.nil?

    start_date = parse_date(params[:start_date])
    end_date = parse_date(params[:end_date])
    return_errors!("Enter a valid start and end date.", 400) if start_date.nil? || end_date.nil?
    return_errors!("End date can't be before the start date.", 400) if end_date < start_date
    return_errors!("Start date can't be in the past.", 400) if start_date < Date.today

    leave = AgentLeaveRequest.new(
      agent_id: agent.id,
      start_date: start_date,
      end_date: end_date,
      leave_type: AgentLeaveRequest::TYPES.include?(params[:leave_type]) ? params[:leave_type] : 'Leave',
      reason: params[:reason]&.strip.presence,
      status: 'Pending'
    )
    save(leave) do |o|
      o.notify_admin_of_request!
      return_success(o.to_pos)
    end
  end

  # Lets an agent withdraw their own request while it's still awaiting a
  # decision — same "only your own" reasoning as update_my_lead/
  # update_my_deal above, narrowed further to Pending only since an
  # Approved/Rejected request is already a closed admin decision.
  def cancel_my_leave_request
    agent = current_agent
    return_errors!("Not signed in.", 401) if agent.nil?

    leave = AgentLeaveRequest[rp[:id]]
    return_errors!("Leave request not found.", 404) if leave.nil?
    return_errors!("This leave request isn't yours.", 403) unless leave.agent_id == agent.id
    return_errors!("Only a pending request can be cancelled.", 400) unless leave.status == 'Pending'

    leave.status = 'Cancelled'
    save(leave) { |o| return_success(o.to_pos) }
  end

  private

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def month_key(date_or_time)
    date_or_time&.strftime("%Y-%m")
  end

  # Oldest -> newest, 6 calendar months including the current one — same
  # window/ordering the old mock's Feb..Jul sample series used.
  def last_six_months
    (0..5).to_a.reverse.map { |i| i.months.ago.beginning_of_month }
  end

  def avg_satisfaction(reviews)
    return nil if reviews.empty?

    ((reviews.sum(&:stars) / reviews.size.to_f) * 20).round(1)
  end
end
