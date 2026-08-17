Sequel.migration do
  # Same move as migrations/0086 for agents: age becomes a value derived from
  # a real date of birth (RamMember#age, backend/src/models/ram_member.rb)
  # instead of a directly-typed number — the `age < 49` rule
  # (models/ram_member.rb#validate) now checks the computed value. `age` is
  # no longer a stored/settable column anywhere (services/ram_members.rb,
  # ram_auth.rb).
  up do
    alter_table(:ram_members) do
      add_column :date_of_birth, Date
      drop_column :age
    end
  end

  down do
    alter_table(:ram_members) do
      add_column :age, Integer
      drop_column :date_of_birth
    end
  end
end
