Sequel.migration do
  change do
    # Referrals — foundation pass. RAM Network (migrations/0020), Clients
    # (migrations/0017), and Properties (migrations/0012) all exist for real
    # now, so — unlike migrations/0016's own comment at the time — these no
    # longer need to be deferred. `client_id`/`property_id` get real FKs,
    # matching Lead#property_id's own "real FK once the target table exists"
    # precedent (migrations/0014). `ram_id` stays as-is (a RamMember#slug
    # string, not this migration's concern — every RAM-portal scoping query
    # already keys off the slug; changing that is a separate, much larger
    # change touching ram_portal.rb/ram_recommendations.rb/current_ram.rb,
    # out of scope here). `agent_slug` is added as a plain nullable string,
    # matching the exact same deferred convention already used everywhere
    # else an Agent is referenced (Property#agent_slug, Lead#agent_slug,
    # SiteVisit#agent_slug, Client#assigned_agent_slug) — introducing a real
    # integer `agent_id` FK here instead would be a new, inconsistent pattern
    # unique to this one table.
    alter_table(:referrals) do
      add_foreign_key :client_id, :clients
      add_foreign_key :property_id, :properties

      # The specific Lead row created alongside this referral (RAM Portal's
      # "Refer a Client" flow creates both in one transaction — see
      # services/ram_portal.rb#create_my_referral) — lets the referral's
      # detail/timeline reach the contact's phone/email/follow-ups without
      # duplicating those columns onto Referral itself. Nullable: admin-
      # logged referrals (services/referrals.rb, `/admin/referrals`) have no
      # associated Lead.
      add_foreign_key :lead_id, :leads

      add_column :agent_slug, String

      add_index :client_id
      add_index :property_id
      add_index :lead_id
      add_index :agent_slug

      # Queried on every RAM Portal request (my_referrals/create_my_referral/
      # update_my_referral, services/ram_portal.rb) but never indexed.
      add_index :ram_id
    end

    # Admin-provisioned RAM accounts (services/ram_members.rb#create, new
    # admin-invite path alongside the existing self-registration flow) get a
    # securely generated temp password emailed to them — same pattern as
    # Client#send_temporary_password_email (services/clients.rb#create).
    # This flag forces one password change before the temp password can keep
    # being reused indefinitely; cleared in RamAuth#update_password/
    # #reset_password once the RAM sets their own. Self-registered RAMs set
    # their own password at signup, so this defaults false for them.
    alter_table(:ram_members) do
      add_column :must_change_password, TrueClass, default: false
    end
  end
end
