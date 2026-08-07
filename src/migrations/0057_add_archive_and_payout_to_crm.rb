Sequel.migration do
  change do
    # Archive/restore lifecycle for the CRM modules — same convention as
    # Properties/Communities/Builders/etc (a real `archived` column, not an
    # overload of Client#status, which is a different concept: a client's
    # engagement state, not whether the record is hidden from the default
    # admin view). Every CRM admin page was hard-delete-only before this;
    # `delete` on each service becomes an archive/restore toggle, with a
    # genuine hard-delete action kept separately for real removal.
    alter_table(:leads) do
      add_column :archived, TrueClass, default: false
      add_index :archived
    end

    alter_table(:clients) do
      add_column :archived, TrueClass, default: false
      add_index :archived
    end

    alter_table(:follow_ups) do
      add_column :archived, TrueClass, default: false
      add_index :archived
    end

    alter_table(:site_visits) do
      add_column :archived, TrueClass, default: false
      add_index :archived
    end

    alter_table(:referrals) do
      add_column :archived, TrueClass, default: false
      add_index :archived

      # Whether the flat `reward` amount has actually been paid out to the
      # RAM — the commission tracking the CRM brief asks for ("view referral
      # commission"). Plain string with an app-level allowed list, same
      # convention as every other status-shaped column in this codebase.
      add_column :payout_status, String, default: 'Pending'
      add_index :payout_status
    end
  end
end
