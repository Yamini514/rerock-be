Sequel.migration do
  change do
    # Singleton settings row for the public site's Contact info — same
    # "one settings row, lazily created on first read/write" pattern as
    # homepage_settings (migrations/0034). Everywhere this data actually
    # lived before was hardcoded in the frontend (lib/seo.js's siteConfig,
    # duplicated again into Footer.js/ContactClient.js's own JSX) with no
    # admin control at all — an admin who needed to change the support
    # phone number or office address had no way to do it without a code
    # change and a redeploy.
    create_table(:contact_settings) do
      primary_key :id

      String :phone, default: ''
      String :email, default: ''
      String :address_street, default: ''
      String :address_locality, default: ''
      String :address_city, default: ''
      String :address_region, default: ''
      String :address_postal_code, default: ''
      Float :latitude
      Float :longitude

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end
  end
end
