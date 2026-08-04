Sequel.migration do
  change do
    create_table(:job_openings) do
      primary_key :id

      String :title, null: false
      String :department, null: false
      String :location, null: false

      # Plain string per lib/data/careers.js's `type` field — the fixed
      # JOB_TYPES list ("Full-time"/"Part-time"/"Contract"/"Internship")
      # stays app-level/frontend-only, same convention as every other
      # enum-shaped field elsewhere (Community#status, Property#status, etc.)
      String :type, null: false

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end
  end
end
