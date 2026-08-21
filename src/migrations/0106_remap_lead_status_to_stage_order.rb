Sequel.migration do
  # Data-only migration. `Lead::STAGE_ORDER` (models/lead.rb) has always
  # documented the funnel as Enquiry -> Qualified Lead -> Site Visit ->
  # Negotiation -> Agreement -> Closed, but every real creation path (Base
  # #create_referral_with_lead!, PublicSiteVisits#create, ClientSiteVisits
  # #create, RamPortal#create_my_lead) actually wrote "New", and the admin
  # Enquiries UI ran on its own separate 7-value vocabulary (lib/data/leads.js
  # LEAD_STATUSES: New/Contacted/Qualified/Site Visit Scheduled/Negotiation/
  # Won/Lost) — never STAGE_ORDER's own values. This backfills every existing
  # row (and its status-history audit trail) onto STAGE_ORDER's vocabulary so
  # the two finally agree, ahead of the app code switching over to it.
  #
  # "New" and "Contacted" both collapse to "Enquiry" — STAGE_ORDER has no
  # distinct "contacted, not yet qualified" stage — and "Won" becomes
  # "Closed" (STAGE_ORDER's actual terminal-success value; this also
  # incidentally makes services/leads.rb#convert_to_client's "status ==
  # Closed" check reachable from the admin UI for the first time). "Lost",
  # "Negotiation" and "Qualified Lead" already match on the Lead side and are
  # listed as no-ops for clarity.
  up do
    status_map = {
      'New' => 'Enquiry',
      'Contacted' => 'Enquiry',
      'Qualified' => 'Qualified Lead',
      'Site Visit Scheduled' => 'Site Visit',
      'Negotiation' => 'Negotiation',
      'Won' => 'Closed',
      'Lost' => 'Lost',
    }

    status_map.each do |old_status, new_status|
      next if old_status == new_status

      from(:leads).where(status: old_status).update(status: new_status)
      from(:lead_status_histories).where(status: old_status).update(status: new_status)
    end
  end

  # Not reversible: "New" and "Contacted" both map to "Enquiry", so the
  # reverse mapping is ambiguous/lossy — same "nothing meaningful to
  # restore" rule migrations/0098 already follows for its own collapsing
  # backfill.
  down do
  end
end
