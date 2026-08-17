Sequel.migration do
  # `community_id` — the RAM Portal's new "Add Referral" form lets a RAM
  # optionally reference a Community as well as (or instead of) a specific
  # Property (see services/ram_portal.rb#create_my_referral).
  # `date` widened from Date to DateTime so "Referral Date and Time" has
  # somewhere to store the time component — same column, no rename.
  up do
    alter_table(:referrals) do
      add_foreign_key :community_id, :communities
      set_column_type :date, DateTime
    end
  end

  down do
    alter_table(:referrals) do
      set_column_type :date, Date
      drop_column :community_id
    end
  end
end
