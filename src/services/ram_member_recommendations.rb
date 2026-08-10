# Admin-facing counterpart to services/ram_recommendations.rb (the RAM
# Portal's own "Recommend Property" flow). Same real `recommendations` table
# (migrations/0051), same `sender_type: "ram", sender_slug: ram.slug` shape —
# this just lets an admin log/browse a recommendation on a RAM's behalf from
# the RAM Details page's Recommendations tab, instead of the RAM doing it
# from their own portal.
#
# Scoped by a `ram_id` (RamMember#id) path param, set by routes.rb via
# `RamMemberRecommendations[r, ram_id: ram_id]` — never trusted from the
# request body. Every create is validated against a real Referral row so the
# frontend can never fabricate a RAM/referral/client relationship that
# doesn't actually exist (see #create's ownership check below).
class App::Services::RamMemberRecommendations < App::Services::Base
  def model; Recommendation; end

  def ram
    @ram ||= RamMember[rp[:ram_id]] || return_errors!("RAM member not found.", 404)
  end

  # `referral_id` (not `client_id`) is the only relationship identifier taken
  # from the request — the client, and the fact that this referral actually
  # belongs to this RAM, are both derived from that one real row, never from
  # anything else the frontend sends. This is what makes "Referral ID is
  # auto-mapped, not manually typed" an enforced backend rule rather than a
  # frontend-only convention.
  def create
    referral = Referral[params[:referral_id]]
    return_errors!("Referral not found.", 404) if referral.nil?
    return_errors!("This referral doesn't belong to this RAM member.", 403) unless referral.ram_id == ram.slug
    return_errors!("This referral has no linked client to recommend a property to.", 422) if referral.client_id.blank?

    client = Client[referral.client_id]
    return_errors!("Client not found.", 404) if client.nil?

    property = Property[params[:property_id]]
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
      priority: "Medium",
      status: params[:status].presence || "Sent"
    )

    save(recommendation) { |o| return_success(o.to_pos.merge('referralId' => referral.id)) }
  end

  # The RAM's own recommendations, sent either by the RAM themselves (portal)
  # or logged on their behalf here — same underlying rows either way, since
  # both write paths use the identical sender_type/sender_slug shape.
  def list
    return_success(
      Recommendation.where(sender_type: "ram", sender_slug: ram.slug)
        .order(Sequel.desc(:created_at)).all.map(&:to_pos)
    )
  end
end
