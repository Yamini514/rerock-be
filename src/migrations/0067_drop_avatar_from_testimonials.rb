Sequel.migration do
  change do
    # Testimonials never had a real image-upload field on the admin form —
    # every "avatar" was either seed data or borrowed from an unrelated
    # existing row (services/testimonials.rb's old rows[0]?.avatar
    # fallback). Dropping it rather than leaving a column nothing can set.
    alter_table(:testimonials) do
      drop_column :avatar
    end
  end
end
