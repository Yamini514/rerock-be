# Unauthenticated — a visitor clicking a RAM's shared referral link
# (`/ref/<code>` or `/properties/<slug>?ref=<code>` on the public site).
# Records the click (analytics/attribution audit trail only — the actual
# permanent attribution happens at conversion time via
# Base#create_referral_with_lead!, when/if the visitor submits an enquiry or
# site-visit request; see services/public_contact.rb/public_site_visits.rb)
# and returns just enough to show a "Referred by <RAM>" banner.
#
# BUSINESS DECISION (undocumented anywhere else, recorded here): links don't
# expire server-side — a RAM/admin deactivates one explicitly
# (services/referral_links.rb#deactivate) rather than it timing out on its
# own. The frontend's own capture (lib/referralAttribution.js) separately
# applies a 30-day local decay to *browser-side* attribution so a stale
# click doesn't attribute a conversion made months later — that's a
# client-side attribution-window policy, not this link's own lifecycle.
class App::Services::PublicReferralLinks < App::Services::Base
  def model; ReferralLink; end

  def click
    link = ReferralLink.where(code: rp[:code], active: true).first
    return_errors!("Referral link not found.", 404) if link.nil?

    link.clicks_count = (link.clicks_count || 0) + 1
    link.last_clicked_at = Time.now
    link.save(validate: false)

    ram = RamMember.where(slug: link.ram_id).first
    property = link.property_id ? Property[link.property_id] : nil

    return_success(
      'code' => link.code,
      'ramName' => ram&.name,
      'property' => property ? { 'id' => property.id, 'slug' => property.slug, 'title' => property.title } : nil
    )
  end
end
