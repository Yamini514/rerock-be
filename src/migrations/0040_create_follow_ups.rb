Sequel.migration do
  change do
    create_table(:follow_ups) do
      primary_key :id
      String :client_name, null: false

      foreign_key :lead_id, :leads
      foreign_key :property_id, :properties
      foreign_key :agent_id, :agents

      Date :due_date, null: false
      String :type, default: 'Call'
      String :priority, default: 'Medium'

      TrueClass :done, default: false
      String :notes, text: true

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :due_date
      index :done
      index :agent_id
    end
  end
end
