# Client Portal's own referral-link generator — general ("refer the
# website") or property-specific ("refer this property"). Same shape as
# services/referral_links.rb (the RAM Portal's own version); this is its
# Client-portal counterpart now that ReferralLink can be owned by either
# (migrations/0104). `code` is an opaque public token (never a raw
# client_id/property_id in a URL — see services/public_referral_links.rb for
# the click-resolve side). Every action here derives the acting client from
# CurrentClient's own JWT, same "never trust an id from params" convention
# as services/client_auth.rb.
class App::Services::ClientReferralLinks < App::Services::Base
  def model; ReferralLink; end

  def mine
    client = CurrentClient.client_obj
    return_errors!("Not signed in.", 401) if client.nil?

    return_success(ReferralLink.where(client_id: client.id).order(Sequel.desc(:created_at)).all.map(&:to_pos))
  end

  # Idempotent by (client, property): a general link (property_id blank)
  # and a given property's link are each generated once and reused on every
  # later share-sheet open, same "find or create" reasoning as RAM's own
  # version.
  def create
    client = CurrentClient.client_obj
    return_errors!("Not signed in.", 401) if client.nil?

    property_id = params[:property_id].presence
    return_errors!("Property not found.", 404) if property_id.present? && Property[property_id].nil?

    existing = ReferralLink.where(client_id: client.id, property_id: property_id, active: true).first
    return return_success(existing.to_pos) if existing

    link = ReferralLink.new(
      client_id: client.id,
      property_id: property_id,
      code: unique_code
    )
    save(link) { |o| return_success(o.to_pos) }
  end

  private

  def unique_code
    loop do
      code = SecureRandom.alphanumeric(8)
      return code unless ReferralLink.where(code: code).first
    end
  end
end
