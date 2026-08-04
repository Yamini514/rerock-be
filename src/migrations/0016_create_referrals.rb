Sequel.migration do
  change do
    create_table(:referrals) do
      primary_key :id

      # RAM Network isn't a built module yet (staff.js's ramTeam is still
      # mock-only) — deferred FK kept as a plain nullable string, same pattern
      # already established for Property#agent_slug (migrations/0012),
      # Lead#agent_slug/ram_id (migrations/0014), and SiteVisit#agent_slug
      # (migrations/0015).
      String :ram_id

      # Client Referral / Agent Referral — plain string with an app-level
      # allowed list (REFERRAL_TYPES in lib/data/referrals.js), same
      # convention as Lead#source/#priority/#status elsewhere.
      String :type

      String :referrer
      String :referred

      # Enquiry Stage / Site Visit Scheduled / Purchase Completed — plain
      # string with an app-level allowed list (REFERRAL_STATUSES).
      String :status, default: 'Enquiry Stage'

      Integer :reward, default: 0
      Date :date

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :status
      index :type
      index :date
    end
  end
end
