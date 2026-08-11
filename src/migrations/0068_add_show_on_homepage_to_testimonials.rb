Sequel.migration do
  change do
    # Per-testimonial homepage curation — previously every single Approved
    # testimonial showed on the homepage carousel unconditionally
    # (services/public_testimonials.rb had no other filter). Defaults to
    # true so existing Approved testimonials keep showing until an admin
    # explicitly curates the list down, same "preserve current behavior"
    # reasoning as Community#featured/#trending/#homepage_visibility.
    alter_table(:testimonials) do
      add_column :show_on_homepage, TrueClass, default: true
    end
  end
end
