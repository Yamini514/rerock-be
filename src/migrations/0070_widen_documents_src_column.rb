Sequel.migration do
  change do
    # `String :src` (migrations/0052) defaults to a length-capped varchar
    # since it wasn't declared `text: true` like the table's own `notes`
    # column — fine for a real S3 URL, but the Admin CRM's Client Documents
    # tab now falls back to a base64 data: URL (no AWS credentials
    # configured in this environment, same fallback convention as
    # ImageUploader's property-photo base64 path), which is many KB/MB long
    # and would otherwise hit Postgres's "value too long for type character
    # varying" on every save.
    alter_table(:documents) do
      set_column_type :src, :text
    end
  end
end
