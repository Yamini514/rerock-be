Sequel.migration do
  change do
    create_table(:career_benefits) do
      primary_key :id

      String :title, null: false
      String :description, text: true, null: false

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end
  end
end
