
Sequel.migration do
  change do
    alter_table(:users) do
      add_column :designation, String
      add_column :department, String
      add_column :reporting_to_id, Integer

      add_index :reporting_to_id
      add_foreign_key [:reporting_to_id], :users, name: :fk_users_reporting_to_id
    end
  end
end
