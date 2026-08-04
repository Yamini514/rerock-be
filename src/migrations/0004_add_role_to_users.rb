Sequel.migration do
  change do
    alter_table(:users) do
      add_column :role_id, Integer
      add_column :is_super_admin, TrueClass, default: false
      add_column :permission_overrides, :jsonb, default: '{"allow":[],"deny":[]}'

      add_index :role_id
      add_foreign_key [:role_id], :roles, name: :fk_users_role_id
    end
  end
end
