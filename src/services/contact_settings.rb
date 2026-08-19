# Singleton settings row for the public site's Contact info (phone, email,
# office address, map coordinates) — same "one settings row, lazily created
# on first read/write" pattern as HomepageSettings (services/
# homepage_settings.rb). Overrides Base#item entirely so the route/frontend
# never needs to know/pass an id; Base's own generic #get/#update both just
# call `item` with no arguments, so this override is all that's needed for
# both to work against the singleton. Same "one service, mounted twice"
# reuse as HomepageSettings — routes.rb wires this exact class's #get under
# the public block too (read-only there, no r.put), instead of a separate
# PublicContactSettings service, since a plain read has nothing to protect.
# Powers the public Contact page/Footer instead of the old hardcoded
# lib/seo.js siteConfig values.
class App::Services::ContactSettings < App::Services::Base
  def model; ContactSetting; end

  def item
    @item ||= model.first || model.create
  end

  def self.fields
    {
      save: [
        :phone, :email, :address_street, :address_locality, :address_city,
        :address_region, :address_postal_code, :latitude, :longitude
      ]
    }
  end
end
