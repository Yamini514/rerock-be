Sequel.migration do
  change do
    create_table(:newsletter_subscribers) do
      primary_key :id
      String :email, null: false
      String :status, default: 'Subscribed'
      String :source, default: 'Website'
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :email, unique: true
    end
  end
end
