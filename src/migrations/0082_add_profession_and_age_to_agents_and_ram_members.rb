Sequel.migration do
  # Both fields are admin-set on the Add/Edit Agent and Add/Edit RAM forms.
  # Age is validated < 49 in App::Models::Agent/RamMember#validate.
  up do
    alter_table(:agents) do
      add_column :profession, String
      add_column :age, Integer
    end
    alter_table(:ram_members) do
      add_column :profession, String
      add_column :age, Integer
    end
  end

  down do
    alter_table(:agents) do
      drop_column :profession
      drop_column :age
    end
    alter_table(:ram_members) do
      drop_column :profession
      drop_column :age
    end
  end
end
