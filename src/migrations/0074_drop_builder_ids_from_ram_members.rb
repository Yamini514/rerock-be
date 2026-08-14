Sequel.migration do
  change do
    # "Builders Handled" is being removed as a concept entirely — a RAM
    # member can sell/recommend any property from any builder, so the
    # builder_ids integer[] FK-array column (migrations/0020) has no more
    # readers/writers anywhere in the app (admin form, detail page, service
    # whitelist). avatar stays — RAM members/admins can still set a real
    # photo, it's just no longer auto-assigned a random stock image.
    alter_table(:ram_members) do
      drop_column :builder_ids
    end
  end
end
