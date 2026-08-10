Sequel.migration do
  change do
    # RAM referral links — general ("bring anyone") or property-specific.
    # `ram_id` is a RamMember#slug string, same convention as
    # Referral#ram_id (see migrations/0059's own comment on why that column
    # isn't touched here). `code` is the opaque public-facing token (never
    # exposes ram_id/property_id in a URL — see services/referral_links.rb).
    create_table(:referral_links) do
      primary_key :id
      String :ram_id, null: false
      foreign_key :property_id, :properties
      String :code, null: false
      Integer :clicks_count, default: 0
      DateTime :last_clicked_at
      TrueClass :active, default: true
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :ram_id
      index :property_id
      index :code, unique: true
    end

    # Which link (if any) produced a given referral — nullable, since most
    # referrals still come from a RAM's own manual "Refer a Client" entry,
    # not a shared link. Purely an attribution/analytics trail; the actual
    # ram_id/property_id attribution already lives on the referral itself
    # (migrations/0059) regardless of how it was created.
    alter_table(:referrals) do
      add_foreign_key :referral_link_id, :referral_links
      add_index :referral_link_id
    end

    # Which referral (if any) this deal fulfills — set when a Deal is
    # auto-created off a completed SiteVisit whose Lead traces back to a
    # real Referral (see models/site_visit.rb#ensure_deal_for_completion!),
    # or resolved from client_id at direct-create time
    # (services/deals.rb#create). Nullable: most deals have no referral
    # behind them at all.
    alter_table(:deals) do
      add_foreign_key :referral_id, :referrals
      add_index :referral_id
    end

    # Commission — the piece that genuinely didn't exist anywhere before
    # this (services/reports.rb's "Commission" was always an Agent-only
    # computed report over agents.commission_earned, unrelated to RAM
    # referrals). One row per Deal that closes against a Referral;
    # created automatically (Deal#ensure_commission_for_closure!) with
    # status PENDING, everything past that is an explicit admin action
    # (services/commissions.rb) — see models/commission.rb's
    # ALLOWED_TRANSITIONS for the enforced state machine.
    create_table(:commissions) do
      primary_key :id
      foreign_key :referral_id, :referrals, null: false
      foreign_key :deal_id, :deals
      String :ram_id, null: false
      Integer :sale_amount, default: 0
      Float :commission_rate, default: 1.0
      Integer :commission_amount, default: 0
      String :status, default: 'PENDING'
      String :approved_by
      DateTime :approved_at
      DateTime :paid_at
      String :notes, text: true
      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :referral_id
      index :deal_id
      index :ram_id
      index :status
    end
  end
end
