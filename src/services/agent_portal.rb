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

    return_success(Deal.where(agent_slug: agent.slug).order(Sequel.desc(:created_at)).all.map(&:to_pos))
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

    allowed = params.slice(:stage, :probability, :value, :closing_date)
    deal.set_fields(allowed, allowed.keys)
    save(deal) { |o| return_success(o.to_pos) }
  end

  def my_leads
    agent = current_agent
    return_errors!("Not signed in.", 401) if agent.nil?

    return_success(Lead.where(agent_slug: agent.slug).order(Sequel.desc(:created_at)).all.map(&:to_pos))
  end

  # Stage/priority/follow-up edits and timeline appends — same "whole array
  # back, already-appended" convention as Leads#fields itself, minus the
  # FK-shaped fields (property_id/community_id/area_id/agent_slug/ram_id):
  # reassignment stays an admin action.
  def update_my_lead
    agent = current_agent
    return_errors!("Not signed in.", 401) if agent.nil?

    lead = Lead[rp[:id]]
    return_errors!("Lead not found.", 404) if lead.nil?
    return_errors!("This lead isn't assigned to you.", 403) unless lead.agent_slug == agent.slug

    allowed = params.slice(:status, :priority, :budget, :next_follow_up, :last_follow_up, :timeline)
    lead.set_fields(allowed, allowed.keys)
    save(lead) { |o| return_success(o.to_pos) }
  end

  def my_site_visits
    agent = current_agent
    return_errors!("Not signed in.", 401) if agent.nil?

    return_success(SiteVisit.where(agent_slug: agent.slug).order(Sequel.desc(:created_at)).all.map(&:to_pos))
  end

  def update_my_site_visit
    agent = current_agent
    return_errors!("Not signed in.", 401) if agent.nil?

    visit = SiteVisit[rp[:id]]
    return_errors!("Site visit not found.", 404) if visit.nil?
    return_errors!("This site visit isn't assigned to you.", 403) unless visit.agent_slug == agent.slug

    allowed = params.slice(:status, :notes, :date, :time)
    visit.set_fields(allowed, allowed.keys)
    save(visit) { |o| return_success(o.to_pos) }
  end

  # Read-only: an agent can see their own assigned clients' CRM record, but
  # editing the client relationship itself (notes/communication_log/
  # invested_properties/reassignment) stays an admin/advisor action via
  # /admin/clients, same reasoning as the Client Portal's own
  # ClientAuth#update_profile excluding invested_properties.
  def my_clients
    agent = current_agent
    return_errors!("Not signed in.", 401) if agent.nil?

    return_success(Client.where(assigned_agent_slug: agent.slug).order(Sequel.desc(:created_at)).all.map(&:to_pos))
  end
end
