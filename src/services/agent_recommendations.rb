# Agent Portal's "Recommend Property" flow — same shape as
# services/ram_recommendations.rb, kept as its own copy for the usual
# "separate identity table, no shared concern" reasoning already
# established across this portal's other services. Replaces
# components/agent/RecommendModal.js's old toast-only stub (it never
# called any API). An agent can only recommend to their own assigned
# clients (Client#assigned_agent_slug == Agent#slug), and only properties
# assigned to them (Property#agent_slug == Agent#slug, or a property one of
# their own leads is interested in — see #create's own comment).
class App::Services::AgentRecommendations < App::Services::Base
  def model; Recommendation; end

  def create
    agent = CurrentAgent.agent_obj
    return_errors!("Not signed in.", 401) if agent.nil?

    client = Client[params[:client_id]]
    return_errors!("Client not found.", 404) if client.nil?
    return_errors!("This client isn't assigned to you.", 403) unless client.assigned_agent_slug == agent.slug

    property = Property.first(slug: params[:property_slug])
    return_errors!("Property not found.", 404) if property.nil?

    # "Assigned to this agent" — same definition the Agent Portal's own
    # Assigned Properties page already uses for what it shows/lets an agent
    # act on (PropertiesClient.js's `myProperties`): either a direct
    # assignment (Property#agent_slug), or the property is one this agent's
    # own lead is interested in. Without this check, any valid property_slug
    # would go through — the frontend's Properties-page filtering was never
    # a real rule, just what that one page happened to list.
    assigned_via_lead = Lead.where(agent_slug: agent.slug, property_id: property.id).first.present?
    unless property.agent_slug == agent.slug || assigned_via_lead
      return_errors!("This property isn't assigned to you.", 403)
    end

    recommendation = Recommendation.new(
      client_id: client.id,
      property_id: property.id,
      client_name: client.name,
      client_phone: client.phone,
      property_slug: property.slug,
      property_title: property.title,
      sender_type: "agent",
      sender_slug: agent.slug,
      remarks: params[:remarks],
      expected_budget: params[:expected_budget],
      priority: params[:priority].presence || "Medium",
      status: "Sent"
    )

    save(recommendation) do |o|
      Notification.create(
        audience: "client",
        recipient_id: client.id,
        type: "recommendation",
        icon: "Sparkles",
        title: "New property recommendation",
        message: "#{agent.name} recommended #{property.title} for you."
      )
      return_success(o.to_pos)
    end
  end

  # The agent's own sent list — no dedicated Agent Portal list page reads
  # this yet, kept for symmetry with services/ram_recommendations.rb#mine.
  def mine
    agent = CurrentAgent.agent_obj
    return_errors!("Not signed in.", 401) if agent.nil?

    return_success(Recommendation.where(sender_type: "agent", sender_slug: agent.slug).order(Sequel.desc(:created_at)).all.map(&:to_pos))
  end
end
