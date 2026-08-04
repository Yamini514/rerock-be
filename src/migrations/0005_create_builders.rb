Sequel.migration do
  change do
    create_table(:builders) do
      primary_key :id
      String :slug, null: false
      String :name, null: false
      Integer :established
      Integer :projects_count, default: 0
      Integer :units_delivered, default: 0
      Float :rating, default: 0
      String :status, default: 'Active'
      String :headquarters
      String :sqft_delivered
      String :website, default: ''
      String :email, default: ''
      String :phone, default: ''
      String :description, text: true
      String :headline
      column :awards, 'text[]', default: '{}'
      column :certifications, 'text[]', default: '{}'
      column :documents, :jsonb, default: '[]'
      String :logo
      column :seo, :jsonb, default: '{"title":"","description":""}'
      Boolean :archived, default: false

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :slug, unique: true
      index :archived
    end
  end
end
