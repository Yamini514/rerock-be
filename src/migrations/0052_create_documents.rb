Sequel.migration do
  change do
    create_table(:documents) do
      primary_key :id

      foreign_key :client_id, :clients, null: false
      # Nullable — matches UploadDocumentModal's "General / not
      # property-specific" option.
      foreign_key :property_id, :properties

      # Denormalized display field, populated at creation time — same
      # convention as Lead#client_name/SiteVisit#client_name/
      # Recommendation#client_name, so the Agent Portal's verification
      # list can render without a join.
      String :client_name

      String :name, null: false
      # Matches frontend/lib/data/portfolio.js's existing
      # DOCUMENT_CATEGORIES exactly — plain string, app-level allowed list,
      # same convention as every other status/category column here.
      String :category, null: false # Agreement | Certificate | Receipt

      # A plain string (blob/data URL), not a real uploaded file — same
      # documented no-real-storage convention as MediaItem#src
      # (migrations/0038): no S3/file-upload wiring exists in this
      # codebase yet.
      String :src, null: false
      String :notes, text: true

      # Pending (client uploaded) -> Verified (agent) -> Approved/Rejected
      # (admin, via the existing generic Approvals queue) — plain string,
      # app-level allowed list.
      String :status, default: 'Pending'
      String :verified_by_agent_slug
      DateTime :verified_at
      Integer :approved_by_user_id
      DateTime :approved_at

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :client_id
      index :status
    end
  end
end
