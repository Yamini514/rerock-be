# Unauthenticated — a visitor clicking a shared referral link (`/ref/<code>`
# or `/properties/<slug>?ref=<code>` on the public site), owned by either a
# RAM (services/referral_links.rb) or a Client (services/
# client_referral_links.rb — migrations/0104 made ReferralLink ownership
# polymorphic). Records the click (analytics/attribution audit trail only —
# the actual permanent attribution happens at conversion time via
# Base#create_referral_with_lead!, when/if the visitor submits a brochure
# request or site-visit request; see services/public_brochure_requests.rb/
# public_site_visits.rb) and returns just enough to show a "Referred by
# <name>" banner, regardless of which kind of owner it is.
#
# BUSINESS DECISION (undocumented anywhere else, recorded here): links don't
# expire server-side — the owner/admin deactivates one explicitly
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

    # A link is owned by exactly one of a RAM member or a Client
    # (models/referral_link.rb#validate) — resolve whichever one it is.
    referrer_name = link.ram_id.present? ? RamMember.where(slug: link.ram_id).first&.name : Client[link.client_id]&.name
    property = link.property_id ? Property[link.property_id] : nil

    return_success(
      'code' => link.code,
      'referrerName' => referrer_name,
      'property' => property ? { 'id' => property.id, 'slug' => property.slug, 'title' => property.title } : nil
    )
  end
end
