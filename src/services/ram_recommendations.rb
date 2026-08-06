# RAM Portal's "Recommend Property" flow — replaces the old
# frontend-only mock (lib/data/recommendations.js's in-memory array,
# mutated by components/ram/RecommendPropertyModal.js with no
# persistence). A RAM can only recommend to their own assigned clients
# (Client#assigned_ram_id == RamMember#slug), same ownership-check
# convention as services/client_reviews.rb.
class App::Services::RamRecommendations < App::Services::Base
  def model; Recommendation; end

  def create
    ram = CurrentRam.ram_obj
    return_errors!("Not signed in.", 401) if ram.nil?

    client = Client[params[:client_id]]
    return_errors!("Client not found.", 404) if client.nil?
    return_errors!("This client isn't assigned to you.", 403) unless client.assigned_ram_id == ram.slug

    property = Property.first(slug: params[:property_slug])
    return_errors!("Property not found.", 404) if property.nil?

    recommendation = Recommendation.new(
      client_id: client.id,
      property_id: property.id,
      client_name: client.name,
      client_phone: client.phone,
      property_slug: property.slug,
      property_title: property.title,
      sender_type: "ram",
      sender_slug: ram.slug,
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
        message: "#{ram.name} recommended #{property.title} for you."
      )
      return_success(o.to_pos)
    end
  end

  # The RAM's own sent list — backs the real "My Recommendations" page.
  def mine
    ram = CurrentRam.ram_obj
    return_errors!("Not signed in.", 401) if ram.nil?

    return_success(Recommendation.where(sender_type: "ram", sender_slug: ram.slug).order(Sequel.desc(:created_at)).all.map(&:to_pos))
  end

  # Status transitions (Sent -> Viewed -> Interested -> ... ) — the only
  # editable field from this scoped endpoint, same "whitelist just the
  # field the page actually edits" convention as AgentPortal#update_my_deal.
  def update
    ram = CurrentRam.ram_obj
    return_errors!("Not signed in.", 401) if ram.nil?

    recommendation = Recommendation[rp[:id]]
    return_errors!("Recommendation not found.", 404) if recommendation.nil?
    return_errors!("This recommendation isn't yours.", 403) unless recommendation.sender_type == "ram" && recommendation.sender_slug == ram.slug

    allowed = params.slice(:status)
    recommendation.set_fields(allowed, allowed.keys)
    save(recommendation) { |o| return_success(o.to_pos) }
  end
end
