Sequel.migration do
  # `facing`/`floor_range` — new Log Enquiry fields (replacing the removed
  # Interested Property/Preferred Area/Agent inputs), capturing the client's
  # own stated preference rather than a specific unit's actual attributes.
  # `quality_score` — Lead Management's quality score/rating (1-5).
  # `loan_percentage` — implemented now but the Log Enquiry UI input stays
  # commented out until Phase 2 (see app/admin/(portal)/enquiries/page.js).
  up do
    alter_table(:leads) do
      add_column :facing, String
      add_column :floor_range, String
      add_column :quality_score, Integer
      add_column :loan_percentage, Float
    end
  end

  down do
    alter_table(:leads) do
      drop_column :facing
      drop_column :floor_range
      drop_column :quality_score
      drop_column :loan_percentage
    end
  end
end
