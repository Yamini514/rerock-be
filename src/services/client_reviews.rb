# Client Portal's own review-submission service — deliberately separate from
# App::Services::Reviews (the Admin Portal's moderation queue over the same
# `reviews` table). A client can only rate things they have a real
# relationship with: their own assigned agent/RAM (Client#assigned_agent_slug/
# #assigned_ram_id), or a property/builder/community they've actually
# purchased into (Client#invested_properties) — never an arbitrary id a
# client happens to guess. Every fresh review lands as status "Pending" and
# only becomes publicly visible once an admin approves it via /admin/reviews.
class App::Services::ClientReviews < App::Services::Base
  def model; Review; end

  REVIEWABLE_TYPES = %w[Agent RamMember Property Builder Community].freeze

  def create
    client = CurrentClient.client_obj
    return_errors!("Not signed in.", 401) if client.nil?

    reviewable_type = params[:reviewable_type]
    reviewable_id = params[:reviewable_id].to_i
    stars = params[:stars].to_i
    quote = params[:quote]&.strip

    return_errors!("Invalid review type.", 400) unless REVIEWABLE_TYPES.include?(reviewable_type)
    return_errors!("Rating must be between 1 and 5 stars.", 400) unless (1..5).cover?(stars)
    return_errors!("Write a short review.", 400) if quote.blank?

    unless owns?(client, reviewable_type, reviewable_id)
      return_errors!("You can only rate an agent/advisor/property/builder/community you have a real relationship with.", 403)
    end

    existing = Review.where(client_id: client.id, reviewable_type: reviewable_type, reviewable_id: reviewable_id).first
    return_errors!("You've already submitted a review for this.", 400) if existing

    review = Review.new(
      client_id: client.id,
      reviewable_type: reviewable_type,
      reviewable_id: reviewable_id,
      stars: stars,
      quote: quote,
      status: "Pending"
    )
    save(review) { |o| return_success(o.to_pos) }
  end

  # The client's own submitted reviews (any status) — so the portal can show
  # "your review is pending" instead of re-showing a submittable form.
  def mine
    client = CurrentClient.client_obj
    return_errors!("Not signed in.", 401) if client.nil?

    return_success(Review.where(client_id: client.id).order(Sequel.desc(:created_at)).all.map(&:to_pos))
  end

  private

  def owns?(client, reviewable_type, reviewable_id)
    case reviewable_type
    when "Agent"
      client.assigned_agent_slug.present? && Agent.where(id: reviewable_id, slug: client.assigned_agent_slug).first.present?
    when "RamMember"
      client.assigned_ram_id.present? && RamMember.where(id: reviewable_id, slug: client.assigned_ram_id).first.present?
    when "Property"
      owned_property_ids(client).include?(reviewable_id)
    when "Builder"
      Property.where(id: owned_property_ids(client), builder_id: reviewable_id).first.present?
    when "Community"
      Property.where(id: owned_property_ids(client), community_id: reviewable_id).first.present?
    else
      false
    end
  end

  def owned_property_ids(client)
    (client.invested_properties || []).map { |p| p['propertyId'] || p[:propertyId] }.compact.map(&:to_i)
  end
end
