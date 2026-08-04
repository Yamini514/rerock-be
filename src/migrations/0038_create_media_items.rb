Sequel.migration do
  change do
    create_table(:media_items) do
      primary_key :id

      # `src` is a plain string (a URL/reference string), not a real
      # uploaded file — per ARCHITECTURE.md's "Known gaps," there is no
      # actual S3/file-upload wiring anywhere in this codebase yet (the
      # Gemfile's aws-sdk-s3 gem + AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY
      # env vars are unused). This table models the media METADATA row
      # only; the admin UI's "Upload" action keeps simulating a file add
      # by producing/storing a URL string here, same as the mock did.
      String :src, null: false
      String :name, null: false

      # Same array-column precedent as Builder#awards/#certifications —
      # db.extension :pg_array (already enabled in app.rb) lets Sequel
      # typecast a plain Ruby array straight onto a text[] column via the
      # ordinary whitelist-and-assign path, no join table needed.
      column :tags, 'text[]', default: Sequel.lit("'{}'")

      # Plain string, not a real users.id FK — same deferred-FK convention
      # as Property#agent_slug/Lead#agent_slug: the mock's `uploadedBy` is
      # just a display name string, and there's no guarantee every name in
      # the mock corresponds to a real seeded staff user.
      String :uploaded_by

      # No separate `uploaded_at` column — `created_at` already IS the
      # natural upload timestamp for a metadata row created at upload time,
      # same convention as the log tables (Activity Logs/Audit Logs/
      # Notifications) reusing `created_at` instead of a redundant second
      # timestamp column. The frontend reads `created_at` wherever the mock
      # read `uploadedAt`.
      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :name
      index :uploaded_by
      index :created_at
    end
  end
end
