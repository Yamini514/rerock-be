Sequel.migration do
  change do
    alter_table(:users) do
      add_column :avatar_url, String, text: true
    end
  end
end
