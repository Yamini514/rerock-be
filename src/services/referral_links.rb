# RAM Portal's own referral-link generator — general ("bring anyone") or
# property-specific. `code` is an opaque public token (never a raw
# ram_id/property_id in a URL — see services/public_referral_links.rb for
# the click-resolve side). Every action here derives the acting RAM from
# CurrentRam's own JWT, same "never trust an id from params" convention as
# services/ram_portal.rb.
class App::Services::ReferralLinks < App::Services::Base
  def model; ReferralLink; end

  def mine
    ram = CurrentRam.ram_obj
    return_errors!("Not signed in.", 401) if ram.nil?

    return_success(ReferralLink.where(ram_id: ram.slug).order(Sequel.desc(:created_at)).all.map(&:to_pos))
  end

  def create
    ram = CurrentRam.ram_obj
    return_errors!("Not signed in.", 401) if ram.nil?

    property_id = params[:property_id].presence
    return_errors!("Property not found.", 404) if property_id.present? && Property[property_id].nil?

    link = ReferralLink.new(
      ram_id: ram.slug,
      property_id: property_id,
      code: unique_code
    )
    save(link) { |o| return_success(o.to_pos) }
  end

  # No hard-delete — a RAM's already-shared link staying resolvable (just no
  # longer accepted for new attribution — see PublicReferralLinks#click)
  # matches the "keep an audit trail, don't destroy real activity" reasoning
  # used for the CRM's own archived-not-deleted convention elsewhere.
  def deactivate
    ram = CurrentRam.ram_obj
    return_errors!("Not signed in.", 401) if ram.nil?

    link = ReferralLink[rp[:id]]
    return_errors!("Link not found.", 404) if link.nil?
    return_errors!("This link isn't yours.", 403) unless link.ram_id == ram.slug

    link.active = false
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
