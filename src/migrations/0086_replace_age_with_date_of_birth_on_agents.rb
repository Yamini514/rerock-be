Sequel.migration do
  # Age moves from a directly-typed number to a value derived from a real
  # date of birth (Agent#age, backend/src/models/agent.rb) — the `age < 49`
  # rule (models/agent.rb#validate) now checks the computed value instead of
  # trusting whatever number was typed in. `age` is no longer a stored/
  # settable column anywhere (services/agents.rb, agent_auth.rb).
  up do
    alter_table(:agents) do
      add_column :date_of_birth, Date
      drop_column :age
    end
  end

  down do
    alter_table(:agents) do
      add_column :age, Integer
      drop_column :date_of_birth
    end
  end
end
