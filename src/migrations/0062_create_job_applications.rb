Sequel.migration do
  change do
    # A candidate's application against an open role — the missing piece
    # between the public Careers page (job_openings, migrations/0030) and
    # the Admin Portal actually seeing who applied. `resume_url`/
    # `cover_letter` are plain text columns holding a base64 data: URL /
    # free text respectively, same "no admin session to spend against the
    # presign endpoint" convention as every other anonymous-visitor upload
    # in this codebase (see services/uploads.rb's own comment on why the
    # Client Portal's self-service upload stays on that same fallback).
    create_table(:job_applications) do
      primary_key :id
      foreign_key :job_opening_id, :job_openings
      String :name, null: false
      String :email, null: false
      String :phone, null: false
      String :resume_url, text: true
      String :cover_letter, text: true
      String :status, default: 'New'
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :job_opening_id
      index :status
    end
  end
end
