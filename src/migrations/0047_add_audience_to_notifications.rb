Sequel.migration do
  change do
    alter_table(:notifications) do
      # "client" | "ram" | "agent" | nil — nil means admin-internal/system
      # notification (the existing behavior: every pre-existing row, plus
      # anything created without picking a portal audience). Real recipient
      # scoping only exists for client/ram/agent; the admin's own feed
      # (services/notifications.rb#list) never filters on this and keeps
      # showing every row regardless of audience.
      add_column :audience, String
      add_index :audience
    end
  end
end
