Sequel.migration do
  change do
    # Property Types taxonomy simplified to Name/Description/Display Order/
    # Active/Allow Search/Homepage Visibility/SEO only — icon/colour styling
    # dropped (services/property_types.rb stopped whitelisting both first;
    # confirmed via full-repo grep that no admin/public/RAM/agent/client
    # surface still reads either column before this migration was added).
    alter_table(:property_types) do
      drop_column :icon
      drop_column :colour
    end
  end
end
