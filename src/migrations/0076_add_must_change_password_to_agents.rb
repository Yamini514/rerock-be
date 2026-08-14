Sequel.migration do
  change do
    # Mirrors migrations/0059's identical addition to ram_members — an
    # admin-created Agent (services/agents.rb#create) now gets a
    # system-generated temp password instead of no password at all, and
    # must set their own real one; AgentAuth#update_password/#reset_password
    # clear this flag once they do (same convention as RamAuth's own
    # equivalents).
    alter_table(:agents) do
      add_column :must_change_password, TrueClass, default: false
    end
  end
end
