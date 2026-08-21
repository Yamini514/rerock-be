# Idempotent sample/demo data loader — Phase 1: Property Catalog.
#
# Transcribes the frontend's mock sample records (frontend/lib/data/*.js) into
# the real Postgres tables built for Property Catalog (migrations 0005-0013),
# so the admin UI has real records to show once `rake db:migrate` and
# `rake db:seed_sample_data` are run against a real database.
#
# Idempotency: every seed_*! method uses Model.find_or_create(natural_key) do |r|
# ... end, the exact idiom already used by the Rakefile's `db:seed` task for
# App::Models::Role/User — re-running this task never duplicates rows.
#
# FK resolution: every reference to an earlier-phase resource (area, location,
# builder, property_type, amenity, property_tag, community, property) is
# looked up fresh via a real DB query at the point of use — never via an
# in-memory map built elsewhere in this file — so each phase is resilient
# regardless of what already exists in the database. If a required parent
# can't be found (shouldn't happen when phases run in order), the offending
# record is skipped with a `warn`, not raised.
#
# Image URLs: the frontend's `lib/images.js` registry builds Unsplash URLs via
# a small `u(id, {w, q})` helper. Reproduced here as IMG so seeded records get
# the exact same real image URLs the mock UI already renders, not placeholders.
#
# Phase 3 (Finance, Marketing/CMS, Ops/Logs) additionally needs real date
# arithmetic (Invoices' due_date, Taxes' period label) that Phases 1-2 never
# required — hence the stdlib `date` require below.

require "date"

module App
  module Seeds
    module SampleData
      module_function

      def unsplash(id, w: 1600, q: 80)
        "https://images.unsplash.com/#{id}?q=#{q}&w=#{w}&auto=format&fit=crop"
      end

      IMG = {
        villa_exterior_1: nil,
        villa_exterior_2: nil,
        villa_exterior_3: nil,
        building_modern_1: nil,
        building_modern_2: nil,
        building_modern_3: nil,
        living_room_1: nil,
        living_room_2: nil,
        kitchen_1: nil,
        bedroom_1: nil,
        bathroom_1: nil,
        dining_room_1: nil,
        skyline_1: nil,
        skyline_aerial_1: nil,
        office_1: nil,
        office_2: nil,
        retail_1: nil,
        warehouse_1: nil,
        land_plot_1: nil,
        land_aerial_1: nil,
        pool_1: nil,
        gym_1: nil,
        clubhouse_1: nil,
        garden_1: nil,
        blueprint_1: nil,
        lobby_1: nil,
        balcony_1: nil,
        home_office_1: nil,
        aerial_community_1: nil,
      }
      IMG[:villa_exterior_1] = unsplash("photo-1600596542815-ffad4c1539a9")
      IMG[:villa_exterior_2] = unsplash("photo-1613977257363-707ba9348227")
      IMG[:villa_exterior_3] = unsplash("photo-1580587771525-78b9dba3b914")
      IMG[:building_modern_1] = unsplash("photo-1512917774080-9991f1c4c750")
      IMG[:building_modern_2] = unsplash("photo-1600607687939-ce8a6c25118c")
      IMG[:building_modern_3] = unsplash("photo-1545324418-cc1a3fa10c00")
      IMG[:living_room_1] = unsplash("photo-1600210492486-724fe5c67fb0")
      IMG[:living_room_2] = unsplash("photo-1616486338812-3dadae4b4ace")
      IMG[:kitchen_1] = unsplash("photo-1600585154340-be6161a56a0c")
      IMG[:bedroom_1] = unsplash("photo-1616594039964-ae9021a400a0")
      IMG[:bathroom_1] = unsplash("photo-1584622650111-993a426fbf0a")
      IMG[:dining_room_1] = unsplash("photo-1617806118233-18e1de247200")
      IMG[:skyline_1] = unsplash("photo-1477959858617-67f85cf4f1df")
      IMG[:skyline_aerial_1] = unsplash("photo-1449844908441-8829872d2607")
      IMG[:office_1] = unsplash("photo-1497366216548-37526070297c")
      IMG[:office_2] = unsplash("photo-1497366754035-f200968a6e72")
      IMG[:retail_1] = unsplash("photo-1568992687947-868a62a9f521")
      IMG[:warehouse_1] = unsplash("photo-1587293852726-70cdb56c2866")
      IMG[:land_plot_1] = unsplash("photo-1500382017468-9049fed747ef")
      IMG[:land_aerial_1] = unsplash("photo-1500937386664-56d1dfef3854")
      IMG[:pool_1] = unsplash("photo-1584735175315-9d5df23860e6")
      IMG[:gym_1] = unsplash("photo-1571902943202-507ec2618e8f")
      IMG[:clubhouse_1] = unsplash("photo-1519167758481-83f550bb49b3")
      IMG[:garden_1] = unsplash("photo-1416879595882-3373a0480b5b")
      IMG[:blueprint_1] = unsplash("photo-1503387762-592deb58ef4e")
      IMG[:lobby_1] = unsplash("photo-1497366811353-6870744d04b2")
      IMG[:balcony_1] = unsplash("photo-1502672260266-1c1ef2d93688")
      IMG[:home_office_1] = unsplash("photo-1524758631624-e2822e304c36")
      IMG[:aerial_community_1] = unsplash("photo-1600585152220-90363fe7e115")
      IMG.freeze

      # Replicates lib/data/{communities,properties}.js's local `trend(base)`
      # helper exactly (same six years, same multipliers) — used for both
      # Community#pricing_trend and Property#pricing_trend jsonb columns.
      # Nested JSON keys stay camelCase (pricePerSqft) to match what the mock
      # UI already expects when it reads pricing_trend back.
      def trend(base)
        [
          { year: "2021", pricePerSqft: (base * 0.72).round },
          { year: "2022", pricePerSqft: (base * 0.81).round },
          { year: "2023", pricePerSqft: (base * 0.89).round },
          { year: "2024", pricePerSqft: (base * 0.96).round },
          { year: "2025", pricePerSqft: (base * 1.0).round },
          { year: "2026", pricePerSqft: (base * 1.08).round },
        ]
      end

      # ---------------------------------------------------------------------
      # 1. Builders (frontend/lib/data/builders.js)
      # ---------------------------------------------------------------------
      BUILDERS = [
        {
          slug: "brigade", name: "Brigade Group", established: 1986, projects_count: 250,
          units_delivered: 42000, rating: 4.7, status: "Active", headquarters: "Bengaluru, Karnataka",
          sqft_delivered: "70 million sq.ft", website: "https://www.brigadegroup.com",
          email: "partnerships@brigadegroup.com", phone: "+91 80 4132 6999",
          description: "One of South India's most trusted developers, known for large-scale integrated townships and consistent delivery.",
          headline: "40 years of building trust across South India",
          awards: ["Developer of the Year — Realty+ 2025", "Best Integrated Township — CREDAI 2024"],
          documents: [
            { name: "RERA Registration Certificate", type: "PDF", date: "2024-01-10" },
            { name: "Certificate of Incorporation", type: "PDF", date: "1986-05-02" },
            { name: "GST Registration", type: "PDF", date: "2017-07-01" },
          ],
        },
        {
          slug: "prestige", name: "Prestige Group", established: 1986, projects_count: 300,
          units_delivered: 58000, rating: 4.8, status: "Active", headquarters: "Bengaluru, Karnataka",
          sqft_delivered: "180 million sq.ft", website: "https://www.prestigeconstructions.com",
          email: "partnerships@prestigeconstructions.com", phone: "+91 80 2559 9000",
          description: "Award-winning developer with a diversified portfolio spanning residential, commercial and hospitality.",
          headline: "India's most awarded real estate brand, 3 years running",
          awards: ["India's Most Trusted Real Estate Brand — 2023, 2024, 2025", "Best Luxury Project — ET RealEstate 2025"],
          documents: [
            { name: "RERA Registration Certificate", type: "PDF", date: "2024-02-14" },
            { name: "Certificate of Incorporation", type: "PDF", date: "1986-03-18" },
            { name: "GST Registration", type: "PDF", date: "2017-07-01" },
          ],
        },
        {
          slug: "sobha", name: "Sobha Limited", established: 1995, projects_count: 180,
          units_delivered: 38000, rating: 4.9, status: "Active", headquarters: "Bengaluru, Karnataka",
          sqft_delivered: "140 million sq.ft", website: "https://www.sobha.com",
          email: "partnerships@sobha.com", phone: "+91 80 4932 5000",
          description: "Renowned for backward-integrated construction and uncompromising build quality — the benchmark for premium delivery.",
          headline: "Engineering excellence in every square foot",
          awards: ["Best Construction Quality — CNBC Awaaz 2024", "Villa Developer of the Year — CREDAI 2025"],
          documents: [
            { name: "RERA Registration Certificate", type: "PDF", date: "2024-01-22" },
            { name: "Certificate of Incorporation", type: "PDF", date: "1995-08-09" },
            { name: "GST Registration", type: "PDF", date: "2017-07-01" },
          ],
        },
        {
          slug: "lodha", name: "Lodha Group", established: 1980, projects_count: 220,
          units_delivered: 71000, rating: 4.6, status: "Active", headquarters: "Mumbai, Maharashtra",
          sqft_delivered: "300 million sq.ft", website: "https://www.lodhagroup.com",
          email: "partnerships@lodhagroup.com", phone: "+91 22 4302 5900",
          description: "India's largest residential developer by sales value, delivering iconic addresses across metros.",
          headline: "India's No.1 real estate developer, 8 years running",
          awards: ["No.1 Real Estate Developer — Forbes India 2025", "Best High-Rise Development — ET RealEstate 2024"],
          documents: [
            { name: "RERA Registration Certificate", type: "PDF", date: "2024-03-05" },
            { name: "Certificate of Incorporation", type: "PDF", date: "1980-11-21" },
            { name: "GST Registration", type: "PDF", date: "2017-07-01" },
          ],
        },
        {
          slug: "aparna", name: "Aparna Constructions", established: 1990, projects_count: 120,
          units_delivered: 26000, rating: 4.5, status: "Active", headquarters: "Hyderabad, Telangana",
          sqft_delivered: "60 million sq.ft", website: "https://www.aparnaconstructions.com",
          email: "partnerships@aparnaconstructions.com", phone: "+91 40 4949 4949",
          description: "Hyderabad's homegrown developer trusted for large gated townships with resort-style amenities.",
          headline: "Building Hyderabad's skyline for three decades",
          awards: ["Best Township — Telangana Real Estate Awards 2024"],
          documents: [
            { name: "RERA Registration Certificate", type: "PDF", date: "2024-01-30" },
            { name: "Certificate of Incorporation", type: "PDF", date: "1990-06-14" },
            { name: "GST Registration", type: "PDF", date: "2017-07-01" },
          ],
        },
        {
          slug: "my-home", name: "My Home Group", established: 1981, projects_count: 90,
          units_delivered: 21000, rating: 4.7, status: "Active", headquarters: "Hyderabad, Telangana",
          sqft_delivered: "45 million sq.ft", website: "https://www.myhomeconstructions.com",
          email: "partnerships@myhomeconstructions.com", phone: "+91 40 6684 6684",
          description: "Diversified conglomerate delivering landmark high-rises and integrated townships in Hyderabad.",
          headline: "Landmark addresses, engineered to last generations",
          awards: ["Best Mixed-Use Development — Telangana Real Estate Awards 2025"],
          documents: [
            { name: "RERA Registration Certificate", type: "PDF", date: "2024-02-19" },
            { name: "Certificate of Incorporation", type: "PDF", date: "1981-09-27" },
            { name: "GST Registration", type: "PDF", date: "2017-07-01" },
          ],
        },
      ].freeze

      def seed_builders!
        BUILDERS.each do |row|
          App::Models::Builder.find_or_create(slug: row[:slug]) do |b|
            b.name = row[:name]
            b.established = row[:established]
            b.projects_count = row[:projects_count]
            b.units_delivered = row[:units_delivered]
            b.rating = row[:rating]
            b.status = row[:status]
            b.headquarters = row[:headquarters]
            b.sqft_delivered = row[:sqft_delivered]
            b.website = row[:website]
            b.email = row[:email]
            b.phone = row[:phone]
            b.description = row[:description]
            b.headline = row[:headline]
            b.awards = Sequel.pg_array(row[:awards])
            b.documents = row[:documents]
          end
        end
        puts "Seeded builders: #{App::Models::Builder.count}"
      end

      # ---------------------------------------------------------------------
      # 2. Property Types (frontend/lib/data/propertyTypes.js)
      # ---------------------------------------------------------------------
      PROPERTY_TYPES = [
        {
          slug: "apartment", name: "Apartment", description: "Multi-storey residential units within gated communities.",
          banner: :building_modern_1, image: :building_modern_1, display_order: 1,
          show_on_homepage: true, allow_search: true,
          seo: { title: "Apartments in Hyderabad", description: "Browse premium apartments across Hyderabad's top micro-markets." },
        },
        {
          slug: "villa", name: "Villa", description: "Independent or semi-independent houses with private land.",
          banner: :villa_exterior_1, image: :villa_exterior_1, display_order: 2,
          show_on_homepage: true, allow_search: true,
          seo: { title: "Villas in Hyderabad", description: "Independent villas in gated communities across Hyderabad." },
        },
        {
          slug: "commercial", name: "Commercial", description: "Offices, retail spaces, and warehousing assets.",
          banner: :office_1, image: :office_1, display_order: 4,
          show_on_homepage: true, allow_search: true,
          seo: { title: "Commercial Properties in Hyderabad", description: "Grade A offices, retail, and warehousing in Hyderabad." },
        },
        {
          # Archived by default — Independent House is excluded from the
          # taxonomy's active options per the admin's current curation
          # (still kept as a real row, not deleted, since existing Property
          # rows may already reference it).
          slug: "independent-house", name: "Independent House",
          description: "Standalone single-family homes, typically on smaller plots than a villa.",
          banner: :villa_exterior_2, image: :villa_exterior_2, display_order: 5,
          show_on_homepage: false, allow_search: true, archived: true,
          seo: { title: "Independent Houses in Hyderabad", description: "Standalone homes across Hyderabad's growth corridors." },
        },
        {
          # Archived by default — see the Independent House comment above;
          # same reasoning applies to Farmhouse.
          slug: "farmhouse", name: "Farmhouse",
          description: "Weekend and leisure homes on larger agricultural or semi-urban land parcels.",
          banner: :garden_1, image: :garden_1, display_order: 6,
          show_on_homepage: false, allow_search: true, archived: true,
          seo: { title: "Farmhouses near Hyderabad", description: "Weekend farmhouses and leisure land near Hyderabad." },
        },
      ].freeze

      def seed_property_types!
        PROPERTY_TYPES.each do |row|
          App::Models::PropertyType.find_or_create(slug: row[:slug]) do |t|
            t.name = row[:name]
            t.description = row[:description]
            t.banner = IMG[row[:banner]]
            t.image = IMG[row[:image]]
            t.display_order = row[:display_order]
            t.show_on_homepage = row[:show_on_homepage]
            t.allow_search = row[:allow_search]
            t.archived = row[:archived] || false
            t.seo = row[:seo]
          end
        end
        puts "Seeded property types: #{App::Models::PropertyType.count}"
      end

      # ---------------------------------------------------------------------
      # 3. Areas (frontend/lib/data/areas.js)
      # ---------------------------------------------------------------------
      AREAS = [
        {
          slug: "kokapet", name: "Kokapet", city: "Hyderabad", state: "Telangana", country: "India",
          image: :skyline_aerial_1, avg_price_per_sqft: 8200, growth_pct: 22, lat: 17.4126, lng: 78.3129,
          description: "Hyderabad's fastest-appreciating micro-market, anchored by the Financial District and premium gated communities.",
          display_order: 1, active: true,
          seo: { title: "Properties in Kokapet, Hyderabad", description: "Explore apartments, villas, and plots in Kokapet, Hyderabad's fastest-appreciating micro-market." },
        },
        {
          slug: "tellapur", name: "Tellapur", city: "Hyderabad", state: "Telangana", country: "India",
          image: :building_modern_2, avg_price_per_sqft: 6800, growth_pct: 18, lat: 17.459, lng: 78.253,
          description: "Emerging IT-corridor suburb with large-format villa communities and open plots.",
          display_order: 2, active: true,
          seo: { title: "Properties in Tellapur, Hyderabad", description: "Villas and open plots in Tellapur's emerging IT-corridor suburb." },
        },
        {
          slug: "financial-district", name: "Financial District", city: "Hyderabad", state: "Telangana", country: "India",
          image: :skyline_1, avg_price_per_sqft: 9600, growth_pct: 27, lat: 17.4239, lng: 78.3776,
          description: "Hyderabad's Grade-A commercial spine — global capability centres, premium high-rises.",
          display_order: 3, active: true,
          seo: { title: "Properties in Financial District, Hyderabad", description: "Grade A commercial and residential properties in Hyderabad's Financial District." },
        },
        {
          slug: "gachibowli", name: "Gachibowli", city: "Hyderabad", state: "Telangana", country: "India",
          image: :building_modern_1, avg_price_per_sqft: 8900, growth_pct: 20, lat: 17.4401, lng: 78.3489,
          description: "Established IT hub with mature social infrastructure and consistent rental demand.",
          display_order: 4, active: true,
          seo: { title: "Properties in Gachibowli, Hyderabad", description: "Apartments and commercial spaces in Gachibowli's established IT hub." },
        },
        {
          slug: "miyapur", name: "Miyapur", city: "Hyderabad", state: "Telangana", country: "India",
          image: :aerial_community_1, avg_price_per_sqft: 5400, growth_pct: 15, lat: 17.4959, lng: 78.3606,
          description: "Metro-connected residential belt offering strong entry-level appreciation.",
          display_order: 5, active: true,
          seo: { title: "Properties in Miyapur, Hyderabad", description: "Metro-connected apartments in Miyapur, Hyderabad." },
        },
        {
          slug: "narsingi", name: "Narsingi", city: "Hyderabad", state: "Telangana", country: "India",
          image: :villa_exterior_3, avg_price_per_sqft: 7100, growth_pct: 24, lat: 17.3937, lng: 78.3323,
          description: "Villa-community corridor bridging Kokapet and Nanakramguda, favoured by end-users.",
          display_order: 6, active: true,
          seo: { title: "Properties in Narsingi, Hyderabad", description: "Luxury villas and plots in Narsingi's villa-community corridor." },
        },
        {
          slug: "kondapur", name: "Kondapur", city: "Hyderabad", state: "Telangana", country: "India",
          image: :building_modern_3, avg_price_per_sqft: 7600, growth_pct: 16, lat: 17.4615, lng: 78.3672,
          description: "Well-connected residential-commercial mix with dense retail and social infrastructure.",
          display_order: 7, active: true,
          seo: { title: "Properties in Kondapur, Hyderabad", description: "Residential and commercial properties in Kondapur, Hyderabad." },
        },
      ].freeze

      def seed_areas!
        AREAS.each do |row|
          App::Models::Area.find_or_create(slug: row[:slug]) do |a|
            a.name = row[:name]
            a.city = row[:city]
            a.state = row[:state]
            a.country = row[:country]
            a.image = IMG[row[:image]]
            a.avg_price_per_sqft = row[:avg_price_per_sqft]
            a.growth_pct = row[:growth_pct]
            a.lat = row[:lat]
            a.lng = row[:lng]
            a.description = row[:description]
            a.display_order = row[:display_order]
            a.active = row[:active]
            a.seo = row[:seo]
          end
        end
        puts "Seeded areas: #{App::Models::Area.count}"
      end

      # ---------------------------------------------------------------------
      # 5. Amenities (frontend/lib/data/amenities.js)
      # ---------------------------------------------------------------------
      AMENITIES = [
        { slug: "infinity-pool", name: "Infinity Pool", icon: "Waves", category: "Outdoor", active: true },
        { slug: "clubhouse-gym", name: "Clubhouse & Gym", icon: "Dumbbell", category: "Clubhouse", active: true },
        { slug: "landscaped-gardens", name: "Landscaped Gardens", icon: "TreePine", category: "Green Spaces", active: true },
        { slug: "24x7-security", name: "24x7 Security", icon: "ShieldCheck", category: "Security", active: true },
        { slug: "power-backup", name: "Power Backup", icon: "Zap", category: "Indoor", active: true },
        { slug: "ev-charging", name: "EV Charging", icon: "BatteryCharging", category: "Parking", active: true },
        { slug: "kids-play-area", name: "Kids' Play Area", icon: "PersonStanding", category: "Children", active: true },
        { slug: "sports-courts", name: "Sports Courts", icon: "Trophy", category: "Sports", active: true },
        { slug: "multipurpose-hall", name: "Multipurpose Hall", icon: "Users", category: "Clubhouse", active: true },
        { slug: "jogging-track", name: "Jogging Track", icon: "Footprints", category: "Outdoor", active: true },
        { slug: "indoor-games-room", name: "Indoor Games Room", icon: "Gamepad2", category: "Indoor", active: true },
        { slug: "guest-parking", name: "Guest Parking", icon: "Car", category: "Parking", active: true },
        { slug: "yoga-meditation-room", name: "Yoga & Meditation Room", icon: "Flower2", category: "Lifestyle", active: true },
        { slug: "medical-room", name: "24x7 Medical Room", icon: "Stethoscope", category: "Medical", active: true },
        { slug: "library-study-room", name: "Library & Study Room", icon: "BookOpen", category: "Education", active: true },
        { slug: "retail-arcade", name: "Retail Arcade", icon: "ShoppingBag", category: "Shopping", active: true },
        { slug: "shuttle-service", name: "Shuttle Service", icon: "Bus", category: "Transport", active: true },
      ].freeze

      def seed_amenities!
        AMENITIES.each do |row|
          App::Models::Amenity.find_or_create(slug: row[:slug]) do |a|
            a.name = row[:name]
            a.icon = row[:icon]
            a.category = row[:category]
            a.active = row[:active]
          end
        end
        puts "Seeded amenities: #{App::Models::Amenity.count}"
      end

      # ---------------------------------------------------------------------
      # 6. Property Tags (frontend/lib/data/propertyTags.js)
      # ---------------------------------------------------------------------
      PROPERTY_TAGS = [
        { slug: "featured", name: "Featured", colour: "#B3421C" },
        { slug: "trending", name: "Trending", colour: "#D97706" },
        { slug: "luxury", name: "Luxury", colour: "#6B5B95" },
        { slug: "premium", name: "Premium", colour: "#3A5A78" },
        { slug: "investment", name: "Investment", colour: "#2E7D32" },
        { slug: "hot-deal", name: "Hot Deal", colour: "#C62828" },
        { slug: "ready-to-move", name: "Ready To Move", colour: "#00796B" },
        { slug: "new-launch", name: "New Launch", colour: "#1565C0" },
        { slug: "exclusive", name: "Exclusive", colour: "#8E24AA" },
        { slug: "sea-view", name: "Sea View", colour: "#0277BD" },
        { slug: "corner-plot", name: "Corner Plot", colour: "#8A9A5B" },
        { slug: "north-facing", name: "North Facing", colour: "#5D4037" },
        { slug: "east-facing", name: "East Facing", colour: "#6D4C41" },
        { slug: "eco-friendly", name: "Eco Friendly", colour: "#388E3C" },
        { slug: "family-friendly", name: "Family Friendly", colour: "#F57C00" },
        { slug: "gated-community", name: "Gated Community", colour: "#455A64" },
      ].freeze

      def seed_property_tags!
        PROPERTY_TAGS.each do |row|
          App::Models::PropertyTag.find_or_create(slug: row[:slug]) do |t|
            t.name = row[:name]
            t.colour = row[:colour]
          end
        end
        puts "Seeded property tags: #{App::Models::PropertyTag.count}"
      end

      # ---------------------------------------------------------------------
      # 7. Communities (frontend/lib/data/communities.js) — references
      #    Builder/Area by slug and Amenities by the shared
      #    `baseAmenities` id list, all resolved via real DB lookups.
      # ---------------------------------------------------------------------
      BASE_AMENITY_SLUGS = %w[
        infinity-pool clubhouse-gym landscaped-gardens 24x7-security power-backup
        ev-charging kids-play-area sports-courts multipurpose-hall jogging-track
        indoor-games-room guest-parking
      ].freeze

      COMMUNITIES = [
        {
          slug: "brigade-horizon", name: "Brigade Horizon", builder_slug: "brigade",
          area_slug: "kokapet", location_slug: "kokapet-phase-1", tagline: "Where the skyline meets serenity",
          status: "Under Construction", featured: true, trending: true, homepage_visibility: true,
          rera: "RERA Approved · P02400005678", price_min: 12_400_000, price_max: 28_500_000,
          unit_types: ["3 BHK", "4 BHK", "Penthouse"], total_units: 480, available_units: 96,
          possession: "Dec 2027", investment_score: 92, growth_pct: 22, last_price_update: "2026-06-25",
          hero_image: :building_modern_1,
          gallery: [:building_modern_1, :living_room_1, :pool_1, :clubhouse_1, :skyline_aerial_1, :lobby_1],
          overview: "Brigade Horizon is a 12-acre high-rise township of five towers rising 38 storeys above Kokapet, framing uninterrupted views of the Financial District skyline. Designed for households who want resort living without leaving the city.",
          master_plan: "Five towers arranged around a 2.5-acre central landscaped courtyard, with a dedicated clubhouse block, elevated jogging deck, and basement + podium parking for over 900 vehicles.",
          amenity_slugs: BASE_AMENITY_SLUGS, pricing_trend_base: 8200,
          nearby: [
            { category: "School", name: "Oakridge International School", distanceKm: 2.1 },
            { category: "Hospital", name: "Continental Hospitals", distanceKm: 3.4 },
            { category: "Metro", name: "Nagole–Raidurg Metro (proposed extension)", distanceKm: 4.8 },
            { category: "Mall", name: "Sarath City Capital Mall", distanceKm: 6.2 },
            { category: "IT Park", name: "Financial District", distanceKm: 3.0 },
          ],
        },
        {
          slug: "prestige-lakeside", name: "Prestige Lakeside Habitat", builder_slug: "prestige",
          area_slug: "tellapur", location_slug: "tellapur-main-road", tagline: "Life, tuned to the rhythm of water",
          status: "Ready To Move", featured: false, trending: true, homepage_visibility: true,
          rera: "RERA Approved · P02400004821", price_min: 9_800_000, price_max: 21_000_000,
          unit_types: ["2 BHK", "3 BHK", "3.5 BHK"], total_units: 620, available_units: 54,
          possession: "Ready To Move", investment_score: 87, growth_pct: 18, last_price_update: "2026-01-10",
          hero_image: :villa_exterior_2,
          gallery: [:villa_exterior_2, :living_room_2, :kitchen_1, :pool_1, :garden_1, :balcony_1],
          overview: "Set beside a private landscaped lake, Prestige Lakeside Habitat spans 22 acres with over 60% open space — a rare density ratio inside the Tellapur growth corridor.",
          master_plan: "Twelve mid-rise towers wrap a central lake and amphitheatre, with a 45,000 sq. ft. clubhouse and dedicated senior-citizen and pet-friendly zones.",
          amenity_slugs: BASE_AMENITY_SLUGS, pricing_trend_base: 6800,
          nearby: [
            { category: "School", name: "Sancta Maria International", distanceKm: 1.8 },
            { category: "Hospital", name: "Citizens Specialty Hospital", distanceKm: 4.1 },
            { category: "Metro", name: "Hitec City Metro", distanceKm: 7.5 },
            { category: "Mall", name: "Inorbit Mall", distanceKm: 8.0 },
            { category: "IT Park", name: "Wipro Circle", distanceKm: 5.2 },
          ],
        },
        {
          slug: "sobha-royal-crest", name: "Sobha Royal Crest", builder_slug: "sobha",
          area_slug: "narsingi", location_slug: "narsingi-villas", tagline: "Villa living, engineered to perfection",
          status: "Ready To Move", featured: true, trending: false, homepage_visibility: true,
          rera: "RERA Approved · P02400003112", price_min: 28_500_000, price_max: 52_000_000,
          unit_types: ["4 BHK Villa", "5 BHK Villa"], total_units: 210, available_units: 22,
          possession: "Ready To Move", investment_score: 95, growth_pct: 24, last_price_update: "2026-07-02",
          hero_image: :villa_exterior_1,
          gallery: [:villa_exterior_1, :villa_exterior_3, :dining_room_1, :pool_1, :garden_1, :bedroom_1],
          overview: "A gated enclave of 210 independent villas built with Sobha's signature backward-integrated construction — precast facades, German engineering, zero-defect delivery.",
          master_plan: "Villas laid along tree-lined boulevards with an 18,000 sq. ft. clubhouse, private pool per villa cluster, and a dedicated central park.",
          amenity_slugs: BASE_AMENITY_SLUGS, pricing_trend_base: 7100,
          nearby: [
            { category: "School", name: "Meridian School", distanceKm: 2.6 },
            { category: "Hospital", name: "Care Hospitals Banjara Hills", distanceKm: 9.4 },
            { category: "Metro", name: "Raidurg Metro", distanceKm: 6.1 },
            { category: "Mall", name: "Sarath City Capital Mall", distanceKm: 5.0 },
            { category: "IT Park", name: "Financial District", distanceKm: 4.2 },
          ],
        },
        {
          slug: "lodha-evergreen", name: "Lodha Evergreen", builder_slug: "lodha",
          area_slug: "gachibowli", location_slug: "gachibowli-central", tagline: "An address that compounds in value",
          status: "Under Construction", featured: false, trending: true, homepage_visibility: true,
          rera: "RERA Approved · P02400006230", price_min: 14_200_000, price_max: 31_500_000,
          unit_types: ["3 BHK", "4 BHK", "Duplex"], total_units: 540, available_units: 128,
          possession: "Mar 2028", investment_score: 90, growth_pct: 20, last_price_update: "2025-11-30",
          hero_image: :building_modern_2,
          gallery: [:building_modern_2, :living_room_1, :gym_1, :clubhouse_1, :skyline_1, :balcony_1],
          overview: "Lodha Evergreen brings the group's signature township format to Gachibowli — four sail-shaped towers set within an 8-acre biodiversity park.",
          master_plan: "Four towers of 42 storeys arranged around a central biodiversity park, elevated sky-deck on the 25th floor, and a triple-height entrance lobby.",
          amenity_slugs: BASE_AMENITY_SLUGS, pricing_trend_base: 8900,
          nearby: [
            { category: "School", name: "Delhi Public School Nacharam", distanceKm: 3.5 },
            { category: "Hospital", name: "AIG Hospitals", distanceKm: 4.0 },
            { category: "Metro", name: "Gachibowli Metro", distanceKm: 1.2 },
            { category: "Mall", name: "Inorbit Mall", distanceKm: 2.8 },
            { category: "IT Park", name: "DLF Cyber City", distanceKm: 2.0 },
          ],
        },
        {
          slug: "my-home-avatar", name: "My Home Avatar", builder_slug: "my-home",
          area_slug: "kondapur", location_slug: "kondapur-main", tagline: "Elevated living, at the centre of it all",
          status: "RERA Approved", featured: false, trending: false, homepage_visibility: true,
          rera: "RERA Approved · P02400002087", price_min: 10_500_000, price_max: 24_000_000,
          unit_types: ["2.5 BHK", "3 BHK", "4 BHK"], total_units: 700, available_units: 210,
          possession: "Jun 2027", investment_score: 85, growth_pct: 16, last_price_update: "2026-05-15",
          hero_image: :building_modern_3,
          gallery: [:building_modern_3, :kitchen_1, :living_room_2, :pool_1, :lobby_1, :home_office_1],
          overview: "My Home Avatar is a 15-acre integrated township in Kondapur with retail high-street frontage, co-working lounges, and dedicated work-from-home suites.",
          master_plan: "Eight towers around a retail promenade, rooftop infinity pool on the amenity block, and dedicated EV-only parking levels.",
          amenity_slugs: BASE_AMENITY_SLUGS, pricing_trend_base: 7600,
          nearby: [
            { category: "School", name: "Glendale Academy", distanceKm: 1.5 },
            { category: "Hospital", name: "Sunshine Hospitals", distanceKm: 2.9 },
            { category: "Metro", name: "Kondapur Metro (upcoming)", distanceKm: 2.0 },
            { category: "Mall", name: "Botanical Gardens Mall", distanceKm: 3.3 },
            { category: "IT Park", name: "Raheja Mindspace", distanceKm: 3.7 },
          ],
        },
        {
          slug: "aparna-zenon", name: "Aparna Zenon", builder_slug: "aparna",
          area_slug: "miyapur", location_slug: "miyapur-metro-belt", tagline: "Smart homes for the next generation",
          status: "Ready To Move", featured: false, trending: false, homepage_visibility: false,
          rera: "RERA Approved · P02400001450", price_min: 6_800_000, price_max: 15_800_000,
          unit_types: ["2 BHK", "3 BHK"], total_units: 860, available_units: 310,
          possession: "Ready To Move", investment_score: 80, growth_pct: 15, last_price_update: "2026-02-20",
          hero_image: :aerial_community_1,
          gallery: [:aerial_community_1, :living_room_1, :gym_1, :pool_1, :garden_1, :bedroom_1],
          overview: "Aparna Zenon is a metro-connected township of 860 smart-enabled homes with app-based access control, EV charging, and a 2-acre central sports arena.",
          master_plan: "Ten towers around a central sports arena, dedicated senior-citizen park, and a full-length retail arcade at the entrance.",
          amenity_slugs: BASE_AMENITY_SLUGS, pricing_trend_base: 5400,
          nearby: [
            { category: "School", name: "Bloom International", distanceKm: 1.1 },
            { category: "Hospital", name: "KIMS Hospital", distanceKm: 3.8 },
            { category: "Metro", name: "Miyapur Metro", distanceKm: 1.6 },
            { category: "Mall", name: "Mytri Mall", distanceKm: 2.4 },
            { category: "IT Park", name: "Hitec City", distanceKm: 9.5 },
          ],
        },
      ].freeze

      def seed_communities!
        COMMUNITIES.each do |row|
          builder = App::Models::Builder.first(slug: row[:builder_slug])
          area = App::Models::Area.first(slug: row[:area_slug])

          if builder.nil? || area.nil?
            warn "[seed_communities!] skipping '#{row[:slug]}': missing builder/area (builder=#{row[:builder_slug]}, area=#{row[:area_slug]})"
            next
          end

          amenity_ids = App::Models::Amenity.where(slug: row[:amenity_slugs]).select_map(:id)

          App::Models::Community.find_or_create(slug: row[:slug]) do |c|
            c.name = row[:name]
            c.builder_id = builder.id
            c.area_id = area.id
            c.tagline = row[:tagline]
            c.status = row[:status]
            c.featured = row[:featured]
            c.trending = row[:trending]
            c.homepage_visibility = row[:homepage_visibility]
            c.rera = row[:rera]
            c.price_min = row[:price_min]
            c.price_max = row[:price_max]
            c.unit_types = Sequel.pg_array(row[:unit_types])
            c.total_units = row[:total_units]
            c.available_units = row[:available_units]
            c.possession = row[:possession]
            c.investment_score = row[:investment_score]
            c.growth_pct = row[:growth_pct]
            c.last_price_update = row[:last_price_update]
            c.hero_image = IMG[row[:hero_image]]
            c.gallery = Sequel.pg_array(row[:gallery].map { |k| IMG[k] })
            c.overview = row[:overview]
            c.master_plan = row[:master_plan]
            c.amenity_ids = Sequel.pg_array(amenity_ids, :integer)
            c.pricing_trend = trend(row[:pricing_trend_base])
            c.nearby = row[:nearby]
          end
        end
        puts "Seeded communities: #{App::Models::Community.count}"
      end

      # ---------------------------------------------------------------------
      # 8. Properties (frontend/lib/data/properties.js) — references
      #    Community/Builder/Area by slug, Property Type by name
      #    (mock's `type` field, e.g. "Apartment"), and Property Tags by the
      #    mock's tag id strings — all resolved via real DB lookups.
      # ---------------------------------------------------------------------
      PROPERTIES = [
        {
          slug: "brigade-horizon-3bhk-tower-a", title: "Luxury 3 BHK", community_slug: "brigade-horizon",
          builder_slug: "brigade", area_slug: "kokapet", location_slug: "kokapet-phase-1", type_name: "Apartment",
          status: "Under Construction", price: 12_400_000, price_per_sqft: 8200, built_up_area: 1512,
          land_area: nil, created_date: "2026-02-10", bedrooms: 3, bathrooms: 3, balconies: 2,
          facing: "East", floor: "14 of 38", rera: true,
          images: [:building_modern_1, :living_room_1, :kitchen_1, :bedroom_1, :bathroom_1, :balcony_1],
          highlights: [
            "Uninterrupted Financial District skyline view", "Vaastu-compliant East-facing layout",
            "Double-height entrance foyer", "Modular kitchen with utility area",
          ],
          description: "A meticulously planned 3 BHK on the 14th floor of Tower A, opening onto uninterrupted views of the Financial District skyline. Layouts are Vaastu-compliant with a dedicated utility and servant's area.",
          floor_plans: [{ label: "3 BHK — 1,512 sq.ft", image: :blueprint_1 }],
          pricing_trend_base: 8200, agent_slug: "rahul-sharma", featured: true,
          tag_slugs: ["featured", "new-launch", "east-facing"],
        },
        {
          slug: "sobha-royal-crest-5bhk-villa", title: "Luxury Villa", community_slug: "sobha-royal-crest",
          builder_slug: "sobha", area_slug: "narsingi", location_slug: "narsingi-villas", type_name: "Villa",
          status: "Ready To Move", price: 52_000_000, price_per_sqft: 9800, built_up_area: 5306,
          land_area: nil, created_date: "2026-01-15", bedrooms: 5, bathrooms: 6, balconies: 4,
          facing: "North-East", floor: "Ground + 2", rera: true,
          images: [:villa_exterior_1, :dining_room_1, :living_room_2, :bedroom_1, :pool_1, :garden_1],
          highlights: [
            "Private plunge pool & landscaped garden", "Home automation pre-wired",
            "4-car covered parking", "Double-height living & dining",
          ],
          description: "A 5 BHK independent villa across Ground + 2 floors with a private plunge pool, home automation pre-wiring, and four-car covered parking — the flagship villa typology at Sobha Royal Crest.",
          floor_plans: [
            { label: "Ground Floor", image: :blueprint_1 },
            { label: "First Floor", image: :blueprint_1 },
          ],
          pricing_trend_base: 9800, agent_slug: "priya-reddy", featured: false,
          tag_slugs: ["luxury", "gated-community", "ready-to-move"],
        },
        {
          slug: "narsingi-premium-open-plot", title: "Premium Open Plot", community_slug: "sobha-royal-crest",
          builder_slug: "sobha", area_slug: "narsingi", location_slug: "narsingi-villas", type_name: "Independent House",
          status: "Available", price: 18_500_000, price_per_sqft: 6800, built_up_area: nil,
          land_area: 2722, created_date: "2026-03-05", bedrooms: nil, bathrooms: nil, balconies: nil,
          facing: "West", floor: nil, rera: true,
          images: [:land_plot_1, :land_aerial_1, :garden_1],
          highlights: [
            "HMDA & RERA approved layout", "Clear title, bank loan approved",
            "Corner plot with 40 ft. road access", "Underground electrical & drainage",
          ],
          description: "A HMDA and RERA approved corner plot with clear title and bank loan approval from all leading lenders, positioned within a gated villa community with underground utilities.",
          floor_plans: [],
          pricing_trend_base: 6800, agent_slug: "arjun-varma", featured: false,
          tag_slugs: ["investment", "corner-plot"],
        },
        {
          slug: "financial-district-grade-a-office", title: "Grade A Office", community_slug: "brigade-horizon",
          builder_slug: "brigade", area_slug: "financial-district", location_slug: "financial-district-core",
          type_name: "Commercial", status: "Available", price: 28_500_000, price_per_sqft: 11_200,
          built_up_area: 2545, land_area: nil, created_date: "2026-04-12", bedrooms: nil, bathrooms: 2,
          balconies: 0, facing: "South", floor: "9 of 22", rera: true,
          images: [:office_1, :office_2, :lobby_1, :building_modern_1],
          highlights: [
            "Pre-leased to MNC tenant, 9.2% rental yield", "LEED Platinum certified building",
            "Column-free floor plate", "24x7 power backup & HVAC",
          ],
          description: "A pre-leased Grade A office floor plate in the Financial District, currently yielding 9.2% annually to an MNC tenant on a 9-year lease with built-in escalations.",
          floor_plans: [{ label: "9th Floor Plate — 2,545 sq.ft", image: :blueprint_1 }],
          pricing_trend_base: 11_200, agent_slug: "sneha-rao", featured: false,
          tag_slugs: ["investment", "premium"],
        },
        {
          slug: "kondapur-high-street-retail", title: "Retail Space", community_slug: "my-home-avatar",
          builder_slug: "my-home", area_slug: "kondapur", location_slug: "kondapur-main", type_name: "Commercial",
          status: "Available", price: 8_200_000, price_per_sqft: 14_500, built_up_area: 565,
          land_area: nil, created_date: "2026-05-08", bedrooms: nil, bathrooms: 1, balconies: 0,
          facing: "Main Road", floor: "Ground", rera: true,
          images: [:retail_1, :building_modern_3, :lobby_1],
          highlights: [
            "Ground-floor, high-street frontage", "Suited for F&B / retail flagship",
            "Footfall from 700+ resident families", "Dedicated loading bay",
          ],
          description: "A ground-floor retail unit fronting My Home Avatar's high-street promenade, capturing footfall from over 700 resident families plus surrounding office catchment.",
          floor_plans: [],
          pricing_trend_base: 14_500, agent_slug: "rahul-sharma", featured: true,
          tag_slugs: ["featured", "hot-deal"],
        },
        {
          slug: "gachibowli-logistics-warehouse", title: "Warehouse", community_slug: "lodha-evergreen",
          builder_slug: "lodha", area_slug: "gachibowli", location_slug: "gachibowli-central", type_name: "Commercial",
          status: "Reserved", price: 42_000_000, price_per_sqft: 4200, built_up_area: 10_000,
          land_area: nil, created_date: "2026-06-18", bedrooms: nil, bathrooms: 2, balconies: 0,
          facing: "Highway", floor: "Ground", rera: false,
          images: [:warehouse_1, :land_aerial_1],
          highlights: [
            "Highway-facing, 32 ft. clear height", "Fire NOC & pollution clearance in place",
            "Dock-leveler loading bays", "3-phase power, 500 KVA sanctioned",
          ],
          description: "A 10,000 sq.ft. Grade A warehouse with 32 ft. clear height, dock-leveler loading bays, and 500 KVA sanctioned power — fire and pollution clearances already in place.",
          floor_plans: [{ label: "Layout Plan", image: :blueprint_1 }],
          pricing_trend_base: 4200, agent_slug: "arjun-varma", featured: false,
          tag_slugs: ["investment"],
        },
        {
          slug: "prestige-lakeside-3bhk", title: "Luxury 3 BHK", community_slug: "prestige-lakeside",
          builder_slug: "prestige", area_slug: "tellapur", location_slug: "tellapur-main-road", type_name: "Apartment",
          status: "Ready To Move", price: 16_800_000, price_per_sqft: 7200, built_up_area: 2333,
          land_area: nil, created_date: "2026-07-02", bedrooms: 3, bathrooms: 3, balconies: 3,
          facing: "North", floor: "6 of 14", rera: true,
          images: [:villa_exterior_2, :living_room_2, :kitchen_1, :balcony_1],
          highlights: ["Direct lake-facing balcony", "Twin covered car parks", "Private terrace garden option"],
          description: "A lake-facing 3 BHK on the 6th floor with three balconies opening onto Prestige Lakeside's private lake and amphitheatre — twin covered car parks included.",
          floor_plans: [{ label: "3 BHK — 2,333 sq.ft", image: :blueprint_1 }],
          pricing_trend_base: 7200, agent_slug: "priya-reddy", featured: false,
          tag_slugs: ["ready-to-move", "north-facing", "family-friendly"],
        },
        {
          slug: "aparna-zenon-2bhk", title: "Smart 2 BHK", community_slug: "aparna-zenon",
          builder_slug: "aparna", area_slug: "miyapur", location_slug: "miyapur-metro-belt", type_name: "Apartment",
          status: "Ready To Move", price: 6_800_000, price_per_sqft: 5400, built_up_area: 1259,
          land_area: nil, created_date: "2026-07-20", bedrooms: 2, bathrooms: 2, balconies: 2,
          facing: "East", floor: "11 of 24", rera: true,
          images: [:aerial_community_1, :living_room_1, :bedroom_1, :gym_1],
          highlights: ["App-based smart home controls", "Metro station 1.6 km", "Zero maintenance backlog"],
          description: "A smart-home enabled 2 BHK with app-based access and lighting control, 1.6 km from Miyapur Metro, in a fully-occupied and well-maintained township.",
          floor_plans: [{ label: "2 BHK — 1,259 sq.ft", image: :blueprint_1 }],
          pricing_trend_base: 5400, agent_slug: "sneha-rao", featured: false,
          tag_slugs: ["ready-to-move", "east-facing", "family-friendly"],
        },
      ].freeze

      def seed_properties!
        PROPERTIES.each do |row|
          community = App::Models::Community.first(slug: row[:community_slug])
          builder = App::Models::Builder.first(slug: row[:builder_slug])
          area = App::Models::Area.first(slug: row[:area_slug])
          property_type = App::Models::PropertyType.first(name: row[:type_name])

          if community.nil? || builder.nil? || area.nil? || property_type.nil?
            warn "[seed_properties!] skipping '#{row[:slug]}': missing FK (community=#{row[:community_slug]}, builder=#{row[:builder_slug]}, area=#{row[:area_slug]}, property_type=#{row[:type_name]})"
            next
          end

          tag_ids = App::Models::PropertyTag.where(slug: row[:tag_slugs]).select_map(:id)

          App::Models::Property.find_or_create(slug: row[:slug]) do |p|
            p.title = row[:title]
            p.community_id = community.id
            p.builder_id = builder.id
            p.area_id = area.id
            p.property_type_id = property_type.id
            p.status = row[:status]
            p.price = row[:price]
            p.price_per_sqft = row[:price_per_sqft]
            p.built_up_area = row[:built_up_area]
            p.land_area = row[:land_area]
            p.created_date = row[:created_date]
            p.bedrooms = row[:bedrooms]
            p.bathrooms = row[:bathrooms]
            p.balconies = row[:balconies]
            p.facing = row[:facing]
            p.floor = row[:floor]
            p.rera = row[:rera]
            p.images = Sequel.pg_array(row[:images].map { |k| IMG[k] })
            p.highlights = Sequel.pg_array(row[:highlights])
            p.description = row[:description]
            p.floor_plans = row[:floor_plans].map { |fp| { label: fp[:label], image: IMG[fp[:image]] } }
            p.pricing_trend = trend(row[:pricing_trend_base])
            p.agent_slug = row[:agent_slug]
            p.featured = row[:featured]
            p.tag_ids = Sequel.pg_array(tag_ids, :integer)
            # amenity_ids: the mock's per-property sample records don't set an
            # amenities list (only Communities do) — left at the migration's
            # default empty array.
            # publish_status: the mock's own `addProperty()` defaults new
            # properties to "Published" (not the migration's DB-level "Draft"
            # default) — matched here since these represent real, existing
            # listings, not freshly-drafted ones.
            p.publish_status = "Published"
          end
        end
        puts "Seeded properties: #{App::Models::Property.count}"
      end

      # ---------------------------------------------------------------------
      # 9. Collections (frontend/lib/data/collections.js)
      #
      # The mock's `id: "featured-properties"` collection is deliberately NOT
      # seeded here — per ARCHITECTURE.md's Collections section, that entry is
      # a computed/virtual view over `properties.featured` in the real system,
      # not a stored row, so there is no real "featured-properties" collection
      # to create. Every other mock collection is seeded below with its
      # display_order preserved as-is from the mock (2..10), even though slot
      # 1 (the virtual entry) is intentionally absent from this table.
      # ---------------------------------------------------------------------
      COLLECTIONS = [
        {
          slug: "luxury-villas", name: "Luxury Villas",
          description: "Independent villas with premium finishes and private amenities.",
          cover_image: :villa_exterior_1, property_slugs: ["sobha-royal-crest-5bhk-villa"],
          active: true, display_order: 2,
        },
        {
          slug: "budget-homes", name: "Budget Homes",
          description: "Well-connected homes under ₹1 Cr for first-time buyers.",
          cover_image: :aerial_community_1, property_slugs: ["aparna-zenon-2bhk"],
          active: true, display_order: 3,
        },
        {
          slug: "best-investment", name: "Best Investment",
          description: "Listings with the strongest rental yield and appreciation potential.",
          cover_image: :office_1,
          property_slugs: ["financial-district-grade-a-office", "gachibowli-logistics-warehouse", "narsingi-premium-open-plot"],
          active: true, display_order: 4,
        },
        {
          slug: "weekend-homes", name: "Weekend Homes",
          description: "Farmhouses and leisure properties for weekend getaways.",
          cover_image: :garden_1, property_slugs: [],
          active: true, display_order: 5,
        },
        {
          slug: "commercial-opportunities", name: "Commercial Opportunities",
          description: "Offices, retail, and warehousing assets for business buyers.",
          cover_image: :lobby_1,
          property_slugs: ["financial-district-grade-a-office", "kondapur-high-street-retail", "gachibowli-logistics-warehouse"],
          active: true, display_order: 6,
        },
        {
          slug: "open-plots", name: "Open Plots",
          description: "RERA-approved, clear-title plots for self-construction or land banking.",
          cover_image: :land_plot_1, property_slugs: ["narsingi-premium-open-plot"],
          active: true, display_order: 7,
        },
        {
          slug: "new-launches", name: "New Launches",
          description: "The latest projects to hit the market.",
          cover_image: :skyline_aerial_1, property_slugs: ["brigade-horizon-3bhk-tower-a"],
          active: true, display_order: 8,
        },
        {
          slug: "ready-to-move", name: "Ready To Move",
          description: "Listings available for immediate possession.",
          cover_image: :villa_exterior_2,
          property_slugs: ["sobha-royal-crest-5bhk-villa", "prestige-lakeside-3bhk", "aparna-zenon-2bhk"],
          active: true, display_order: 9,
        },
        {
          slug: "editors-picks", name: "Editor's Picks",
          description: "Our advisory team's top recommendations this month.",
          cover_image: :building_modern_2,
          property_slugs: ["brigade-horizon-3bhk-tower-a", "sobha-royal-crest-5bhk-villa"],
          active: true, display_order: 10,
        },
      ].freeze

      def seed_collections!
        COLLECTIONS.each do |row|
          property_ids = App::Models::Property.where(slug: row[:property_slugs]).select_map(:id)
          missing = row[:property_slugs] - App::Models::Property.where(slug: row[:property_slugs]).select_map(:slug)
          warn "[seed_collections!] '#{row[:slug]}': skipping unresolved property slugs #{missing}" if missing.any?

          App::Models::Collection.find_or_create(slug: row[:slug]) do |c|
            c.name = row[:name]
            c.description = row[:description]
            c.cover_image = IMG[row[:cover_image]]
            c.property_ids = Sequel.pg_array(property_ids, :integer)
            c.active = row[:active]
            c.display_order = row[:display_order]
          end
        end
        puts "Seeded collections: #{App::Models::Collection.count}"
      end

      # =======================================================================
      # PHASE 2: CRM (Leads, Site Visits, Referrals, Clients, Deals) and Agent
      # Network (Agents, RAM Members, Portfolio Members).
      #
      # Idempotency — two different strategies, by design:
      # - Agents / RAM Members / Portfolio Members / Clients have real natural
      #   keys in their mock sample data (slug/email) — same
      #   find_or_create(natural_key) do |r| ... end idiom as Phase 1.
      # - Leads / Site Visits / Referrals / Deals have NO natural unique key in
      #   their mock sample data (no slug/email-like field, and several sibling
      #   rows even share the same client_name). Rather than inventing a
      #   synthetic key that doesn't exist in the source of truth, each of
      #   these four seed_*! methods is guarded at the top with
      #   `return if Model.count.positive?` and uses plain Model.create per
      #   row. This still satisfies "running rake db:seed_sample_data twice
      #   never duplicates rows" — it just grants that guarantee at the method
      #   level instead of the row level.
      #
      # FK resolution to Phase 1 resources (Property/Community/Area) uses the
      # same "fresh real DB query by slug at the point of use" pattern as
      # Phase 1. `agent_slug`/`ram_id` columns everywhere (Lead, SiteVisit,
      # Referral, Client#assigned_agent_slug/#assigned_ram_id, Deal) are still
      # plain deferred strings, not real FKs (see each migration's own
      # comments) — so the mock's string values are copied straight across
      # with no lookup at all.
      #
      # Self-referential Client#referred_by_id is seeded in two passes: pass 1
      # find_or_creates every client by email with every field except
      # referred_by_id; pass 2 (after every client row is guaranteed to exist)
      # walks the CLIENTS array again and sets referred_by_id via a
      # mock_id -> email lookup table.
      #
      # `mock_id` tags: several arrays below (RAM_MEMBERS, LEADS, CLIENTS)
      # carry a `mock_id:` key (e.g. "ram1", "LD-2101", "c1") that mirrors the
      # frontend mock's own id. This is NOT a stored column anywhere — it only
      # exists so a later array in this same file can cross-reference the
      # right row after the fact (Portfolio Members -> RAM Members,
      # Site Visits -> Leads, Client -> Client) without inventing a fake
      # persisted key.
      # =======================================================================

      def avatar_url(seed)
        "https://i.pravatar.cc/256?img=#{seed}"
      end

      # Mirrors lib/utils.js's slugify() closely enough for our purposes: RAM
      # Members have no slug in the mock (staff.js's ramTeam uses "ram1"/
      # "ram2"/"ram3" as a sequential id, not a display slug — see
      # migrations/0020's own comment), so a real one is generated from the
      # name at create time, same shape the Agents' Add form already uses.
      def slugify(name)
        name.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
      end

      # ---------------------------------------------------------------------
      # 10. Agents (frontend/lib/data/agents.js)
      # ---------------------------------------------------------------------
      AGENTS = [
        {
          slug: "rahul-sharma", name: "Rahul Sharma", role: "Senior Investment Advisor",
          email: "rahul.sharma@rerockrealty.com", phone: "+91 98480 12345", whatsapp: "919848012345",
          avatar: 11, specialization: "Luxury Apartments & Villas", deals_closed: 214, rating: 4.9,
          experience_years: 11, strong_area_slugs: ["kokapet", "financial-district"],
          address: "REROCK Realty, Financial District, Hyderabad", status: "Active",
          territory: "Kokapet & Financial District", bookings: 18, revenue: 42_800_000,
          conversion_rate: 7.2, commission_rate: 1.5, commission_earned: 642_000, pending_commission: 96_000,
          leads_assigned: 54, joined_date: "2015-04-01",
          commission_monthly: [
            { month: "May", earned: 186_000 }, { month: "Jun", earned: 212_000 }, { month: "Jul", earned: 244_000 },
          ],
          tasks: [
            { id: "at1", title: "Follow up with Vikram Malhotra on Prestige Lakeside", done: false },
            { id: "at2", title: "Share pricing sheet with Divya Prasad", done: true },
          ],
          attendance: [
            { date: "2026-07-16", status: "Present" }, { date: "2026-07-17", status: "Present" },
            { date: "2026-07-18", status: "Half Day" },
          ],
          properties_sold: [
            { id: "ps1", name: "Prestige Lakeside — 3 BHK", value: 13_000_000, date: "2023-05-14" },
            { id: "ps2", name: "Financial District Grade A Office", value: 28_500_000, date: "2021-07-20" },
          ],
          properties_assigned: [
            { id: "pa1", name: "Brigade Horizon — Tower B", status: "In Progress" },
            { id: "pa2", name: "Kokapet Skyline Residences", status: "In Progress" },
          ],
          documents: [
            { id: "ad1", name: "Aadhaar Card", date: "2015-04-01", type: "Government ID" },
            { id: "ad2", name: "PAN Card", date: "2015-04-01", type: "PAN" },
            { id: "ad3", name: "Employment Agreement", date: "2015-04-01", type: "Agreement" },
            { id: "ad4", name: "RERA Agent Certification", date: "2016-02-10", type: "Certificate" },
            { id: "ad5", name: "Offer Letter", date: "2015-03-20", type: "Offer Letter" },
          ],
          activity_log: [
            { title: "Lead assigned — L-1042", time: "2026-07-17 09:58 AM", done: true },
            { title: "Called Vikram Malhotra", time: "2026-07-16 02:30 PM", done: true },
            { title: "Follow-up completed — Divya Prasad", time: "2026-07-15 11:00 AM", done: true },
            { title: "Site visit scheduled — Prestige Lakeside", time: "2026-07-14 04:00 PM", done: true },
            { title: "Booking confirmed — Financial District Office", time: "2021-07-20 10:00 AM", done: true },
            { title: "Commission generated — ₹2,44,000", time: "2026-07-10 05:00 PM", done: true },
            { title: "Logged in — Chrome · Windows", time: "2026-07-17 08:40 AM", done: true },
          ],
        },
        {
          slug: "priya-reddy", name: "Priya Reddy", role: "Investment Advisor",
          email: "priya.reddy@rerockrealty.com", phone: "+91 98490 22456", whatsapp: "919849022456",
          avatar: 47, specialization: "Gated Communities & Townships", deals_closed: 168, rating: 4.8,
          experience_years: 8, strong_area_slugs: ["tellapur", "gachibowli"],
          address: "REROCK Realty, Gachibowli, Hyderabad", status: "Active",
          territory: "Tellapur & Gachibowli", bookings: 14, revenue: 31_200_000,
          conversion_rate: 6.4, commission_rate: 1.5, commission_earned: 468_000, pending_commission: 72_000,
          leads_assigned: 42, joined_date: "2018-06-15",
          commission_monthly: [
            { month: "May", earned: 140_000 }, { month: "Jun", earned: 152_000 }, { month: "Jul", earned: 176_000 },
          ],
          tasks: [{ id: "pt1", title: "Confirm site visit for Kiran Kumar Reddy", done: true }],
          attendance: [
            { date: "2026-07-16", status: "Present" }, { date: "2026-07-17", status: "Present" },
            { date: "2026-07-18", status: "Present" },
          ],
          properties_sold: [
            { id: "ps3", name: "Aparna Zenon — 2 BHK", value: 6_800_000, date: "2023-01-30" },
            { id: "ps4", name: "Brigade Horizon — Penthouse", value: 12_400_000, date: "2024-01-20" },
          ],
          properties_assigned: [{ id: "pa3", name: "Sobha Royal Crest — Phase 2 Villa", status: "In Progress" }],
          documents: [
            { id: "pd1", name: "Aadhaar Card", date: "2018-06-15", type: "Government ID" },
            { id: "pd2", name: "PAN Card", date: "2018-06-15", type: "PAN" },
            { id: "pd3", name: "Employment Agreement", date: "2018-06-15", type: "Agreement" },
            { id: "pd4", name: "RERA Agent Certification", date: "2018-09-02", type: "Certificate" },
            { id: "pd5", name: "Offer Letter", date: "2018-06-01", type: "Offer Letter" },
          ],
          activity_log: [
            { title: "Lead assigned — L-1108", time: "2026-07-16 10:20 AM", done: true },
            { title: "Called Kiran Kumar Reddy", time: "2026-07-15 03:10 PM", done: true },
            { title: "Follow-up completed — Meenal Deshpande", time: "2026-07-13 12:00 PM", done: true },
            { title: "Site visit scheduled — Sobha Royal Crest", time: "2026-07-11 09:30 AM", done: true },
            { title: "Booking confirmed — Brigade Horizon Penthouse", time: "2024-01-20 11:00 AM", done: true },
            { title: "Logged in — Chrome · Windows", time: "2026-07-17 08:35 AM", done: true },
          ],
        },
        {
          slug: "arjun-varma", name: "Arjun Varma", role: "Commercial & Plots Specialist",
          email: "arjun.varma@rerockrealty.com", phone: "+91 90003 34567", whatsapp: "919000334567",
          avatar: 14, specialization: "Open Plots & Commercial Assets", deals_closed: 132, rating: 4.7,
          experience_years: 9, strong_area_slugs: ["narsingi", "miyapur"],
          address: "REROCK Realty, Narsingi, Hyderabad", status: "On Leave",
          territory: "Narsingi & Miyapur", bookings: 9, revenue: 24_600_000,
          conversion_rate: 5.8, commission_rate: 1.25, commission_earned: 307_500, pending_commission: 45_000,
          leads_assigned: 27, joined_date: "2017-02-10",
          commission_monthly: [
            { month: "May", earned: 96_000 }, { month: "Jun", earned: 102_000 }, { month: "Jul", earned: 109_500 },
          ],
          tasks: [{ id: "vt1", title: "Renew RERA documentation for Financial District Office", done: false }],
          attendance: [
            { date: "2026-07-16", status: "Present" }, { date: "2026-07-17", status: "Leave" },
            { date: "2026-07-18", status: "Leave" },
          ],
          properties_sold: [{ id: "ps5", name: "Financial District — Grade A Office", value: 42_000_000, date: "2020-11-12" }],
          properties_assigned: [{ id: "pa4", name: "Narsingi Open Plots — Phase 3", status: "In Progress" }],
          documents: [
            { id: "vd1", name: "Aadhaar Card", date: "2017-02-10", type: "Government ID" },
            { id: "vd2", name: "PAN Card", date: "2017-02-10", type: "PAN" },
            { id: "vd3", name: "Employment Agreement", date: "2017-02-10", type: "Agreement" },
            { id: "vd4", name: "RERA Agent Certification", date: "2017-05-18", type: "Certificate" },
            { id: "vd5", name: "Offer Letter", date: "2017-01-25", type: "Offer Letter" },
          ],
          activity_log: [
            { title: "Lead assigned — L-0987", time: "2026-07-14 01:15 PM", done: true },
            { title: "Called Srinivas Rao", time: "2026-07-13 04:45 PM", done: true },
            { title: "Follow-up pending — RERA renewal", time: "2026-07-12 10:00 AM", done: false },
            { title: "Site visit scheduled — Narsingi Plots", time: "2026-07-09 11:00 AM", done: true },
            { title: "Booking confirmed — Financial District Office", time: "2020-11-12 09:00 AM", done: true },
            { title: "Logged in — Edge · Windows", time: "2026-07-16 09:00 AM", done: true },
          ],
        },
        {
          slug: "sneha-rao", name: "Sneha Rao", role: "Client Relationship Manager",
          email: "sneha.rao@rerockrealty.com", phone: "+91 91000 45678", whatsapp: "919100045678",
          avatar: 45, specialization: "Portfolio & Post-Sale Advisory", deals_closed: 189, rating: 4.9,
          experience_years: 10, strong_area_slugs: ["kondapur", "financial-district"],
          address: "REROCK Realty, Kondapur, Hyderabad", status: "Active",
          territory: "Kondapur & Financial District", bookings: 16, revenue: 35_400_000,
          conversion_rate: 6.9, commission_rate: 1.5, commission_earned: 531_000, pending_commission: 63_000,
          leads_assigned: 48, joined_date: "2016-09-20",
          commission_monthly: [
            { month: "May", earned: 168_000 }, { month: "Jun", earned: 178_000 }, { month: "Jul", earned: 185_000 },
          ],
          tasks: [{ id: "st1", title: "Send onboarding documents to Ayesha Khan", done: true }],
          attendance: [
            { date: "2026-07-16", status: "Present" }, { date: "2026-07-17", status: "Present" },
            { date: "2026-07-18", status: "Present" },
          ],
          properties_sold: [{ id: "ps6", name: "Kondapur High-Street Retail", value: 16_800_000, date: "2025-06-01" }],
          properties_assigned: [{ id: "pa5", name: "Sobha Royal Crest — Villa 42", status: "In Progress" }],
          documents: [
            { id: "sd1", name: "Aadhaar Card", date: "2016-09-20", type: "Government ID" },
            { id: "sd2", name: "PAN Card", date: "2016-09-20", type: "PAN" },
            { id: "sd3", name: "Employment Agreement", date: "2016-09-20", type: "Agreement" },
            { id: "sd4", name: "RERA Agent Certification", date: "2017-01-12", type: "Certificate" },
            { id: "sd5", name: "Offer Letter", date: "2016-09-05", type: "Offer Letter" },
          ],
          activity_log: [
            { title: "Lead assigned — L-1201", time: "2026-07-16 02:00 PM", done: true },
            { title: "Called Ayesha Khan", time: "2026-07-15 09:40 AM", done: true },
            { title: "Follow-up completed — Ayesha Khan onboarding", time: "2026-07-14 03:20 PM", done: true },
            { title: "Site visit scheduled — Kondapur Retail", time: "2026-05-25 10:00 AM", done: true },
            { title: "Booking confirmed — Kondapur High-Street Retail", time: "2025-06-01 11:00 AM", done: true },
            { title: "Logged in — Safari · macOS", time: "2026-07-16 08:15 AM", done: true },
          ],
        },
      ].freeze

      def seed_agents!
        AGENTS.each do |row|
          strong_area_ids = App::Models::Area.where(slug: row[:strong_area_slugs]).select_map(:id)

          App::Models::Agent.find_or_create(slug: row[:slug]) do |a|
            a.name = row[:name]
            a.role = row[:role]
            a.email = row[:email]
            a.phone = row[:phone]
            a.whatsapp = row[:whatsapp]
            a.avatar = avatar_url(row[:avatar])
            a.specialization = row[:specialization]
            a.deals_closed = row[:deals_closed]
            a.rating = row[:rating]
            a.experience_years = row[:experience_years]
            a.strong_area_ids = Sequel.pg_array(strong_area_ids, :integer)
            a.address = row[:address]
            a.status = row[:status]
            a.territory = row[:territory]
            a.bookings = row[:bookings]
            a.revenue = row[:revenue]
            a.conversion_rate = row[:conversion_rate]
            a.commission_rate = row[:commission_rate]
            a.commission_earned = row[:commission_earned]
            a.pending_commission = row[:pending_commission]
            a.leads_assigned = row[:leads_assigned]
            a.joined_date = row[:joined_date]
            a.commission_monthly = row[:commission_monthly]
            a.tasks = row[:tasks]
            a.attendance = row[:attendance]
            a.properties_sold = row[:properties_sold]
            a.properties_assigned = row[:properties_assigned]
            a.documents = row[:documents]
            a.activity_log = row[:activity_log]
          end
        end
        puts "Seeded agents: #{App::Models::Agent.count}"
      end

      # ---------------------------------------------------------------------
      # 11. RAM Members (frontend/lib/data/staff.js's ramTeam[])
      # ---------------------------------------------------------------------
      RAM_MEMBERS = [
        {
          mock_id: "ram1", name: "Deepak Suri", email: "deepak.s@rerockrealty.com", avatar: 33,
          designation: "Senior RAM", region: "West Hyderabad", phone: "9848011101", default_commission_rate: 1.5,
          profession: "Real Estate Advisor", date_of_birth: "1988-04-12",
          deals_this_quarter: 18, status: "Active", satisfaction: 4.6, renewal_rate: 88, avg_response_time_hours: 3,
          experience_years: 7, revenue_managed: 8_600_000, conversion_rate_pct: 74, referral_generated: 1_250_000,
          recommendations: [
            { id: "r1", client: "Vikram Malhotra", property: "Prestige Lakeside — 3 BHK", status: "Accepted" },
            { id: "r2", client: "Meenal Deshpande", property: "Aparna Zenon — 3 BHK", status: "Sent" },
          ],
          reports: [{ id: "rp1", name: "Q2 Portfolio Review — Deepak Suri", date: "2026-07-01" }],
          performance: [
            { month: "Apr", value: 12 }, { month: "May", value: 15 }, { month: "Jun", value: 17 }, { month: "Jul", value: 18 },
          ],
          activities: [
            { title: "Called Vikram Malhotra re: Prestige Lakeside pricing", time: "2026-07-18 11:20 AM", done: true },
            { title: "Site visit — Prestige Lakeside with Meenal Deshpande", time: "2026-07-16 03:00 PM", done: true },
            { title: "Logged in — Chrome · Windows", time: "2026-07-16 09:05 AM", description: "IP 49.207.12.44", done: true },
            { title: "Sent recommendation — Aparna Zenon 3 BHK", time: "2026-07-14 05:40 PM", done: true },
            { title: "Assigned client Meenal Deshpande", time: "2026-07-01 09:00 AM", done: true },
          ],
          documents: [
            { id: "rd1", name: "RERA Certification — Deepak Suri", date: "2024-01-15", type: "Certificate" },
            { id: "rd2", name: "Aadhaar Card", date: "2020-06-01", type: "Identity Proof" },
            { id: "rd3", name: "Employment Agreement", date: "2020-06-01", type: "Employment Document" },
            { id: "rd4", name: "Non-Compete Contract", date: "2020-06-01", type: "Contract" },
          ],
        },
        {
          mock_id: "ram2", name: "Neha Kapoor", email: "neha.k@rerockrealty.com", avatar: 41,
          designation: "Senior RAM", region: "Financial District", phone: "9848011102", default_commission_rate: 1.5,
          profession: "Real Estate Advisor", date_of_birth: "1985-09-24",
          deals_this_quarter: 22, status: "Active", satisfaction: 4.8, renewal_rate: 92, avg_response_time_hours: 2,
          experience_years: 9, revenue_managed: 11_400_000, conversion_rate_pct: 81, referral_generated: 1_840_000,
          recommendations: [
            { id: "r3", client: "Kiran Kumar Reddy", property: "Sobha Royal Crest — Phase 2 Villa", status: "Accepted" },
            { id: "r4", client: "Ayesha Khan", property: "Brigade Horizon — Tower B", status: "Pending" },
          ],
          reports: [{ id: "rp2", name: "Q2 Portfolio Review — Neha Kapoor", date: "2026-07-01" }],
          performance: [
            { month: "Apr", value: 16 }, { month: "May", value: 19 }, { month: "Jun", value: 20 }, { month: "Jul", value: 22 },
          ],
          activities: [
            { title: "Called Kiran Kumar Reddy re: Sobha Royal Crest handover", time: "2026-07-17 02:15 PM", done: true },
            { title: "Meeting — Ayesha Khan portfolio review", time: "2026-07-15 11:00 AM", done: true },
            { title: "Logged in — Safari · macOS", time: "2026-07-15 08:50 AM", description: "IP 49.207.13.9", done: true },
            { title: "Sent recommendation — Brigade Horizon Tower B", time: "2026-07-12 04:10 PM", done: true },
            { title: "Assigned client Kiran Kumar Reddy", time: "2026-06-20 10:00 AM", done: true },
          ],
          documents: [
            { id: "rd5", name: "RERA Certification — Neha Kapoor", date: "2023-05-10", type: "Certificate" },
            { id: "rd6", name: "PAN Card", date: "2019-03-12", type: "Identity Proof" },
            { id: "rd7", name: "Employment Agreement", date: "2019-03-12", type: "Employment Document" },
            { id: "rd8", name: "Non-Compete Contract", date: "2019-03-12", type: "Contract" },
          ],
        },
        {
          mock_id: "ram3", name: "Manoj Pillai", email: "manoj.p@rerockrealty.com", avatar: 38,
          designation: "RAM", region: "North Hyderabad", phone: "9848011103", default_commission_rate: 1.0,
          profession: "Real Estate Advisor", date_of_birth: "1992-01-30",
          deals_this_quarter: 14, status: "Active", satisfaction: 4.4, renewal_rate: 81, avg_response_time_hours: 5,
          experience_years: 5, revenue_managed: 6_200_000, conversion_rate_pct: 68, referral_generated: 780_000,
          recommendations: [{ id: "r5", client: "Srinivas Rao", property: "Kondapur High-Street Retail", status: "Sent" }],
          reports: [{ id: "rp3", name: "Q2 Portfolio Review — Manoj Pillai", date: "2026-07-01" }],
          performance: [
            { month: "Apr", value: 10 }, { month: "May", value: 11 }, { month: "Jun", value: 13 }, { month: "Jul", value: 14 },
          ],
          activities: [
            { title: "Called Srinivas Rao re: Kondapur retail lease renewal", time: "2026-07-16 01:30 PM", done: true },
            { title: "Property visit — Kondapur High-Street Retail", time: "2026-07-11 10:00 AM", done: true },
            { title: "Logged in — Edge · Windows", time: "2026-07-11 09:00 AM", description: "IP 49.207.14.20", done: true },
            { title: "Sent recommendation — Kondapur High-Street Retail", time: "2026-07-05 03:45 PM", done: true },
            { title: "Assigned client Srinivas Rao", time: "2026-06-15 09:30 AM", done: true },
          ],
          documents: [
            { id: "rd9", name: "RERA Certification — Manoj Pillai", date: "2022-08-20", type: "Certificate" },
            { id: "rd10", name: "Aadhaar Card", date: "2021-11-02", type: "Identity Proof" },
            { id: "rd11", name: "Employment Agreement", date: "2021-11-02", type: "Employment Document" },
            { id: "rd12", name: "Non-Compete Contract", date: "2021-11-02", type: "Contract" },
          ],
        },
      ].freeze

      def seed_ram_members!
        RAM_MEMBERS.each do |row|
          App::Models::RamMember.find_or_create(email: row[:email]) do |r|
            r.slug = slugify(row[:name])
            r.name = row[:name]
            r.avatar = avatar_url(row[:avatar])
            r.designation = row[:designation]
            r.region = row[:region]
            r.default_commission_rate = row[:default_commission_rate]
            r.profession = row[:profession]
            r.date_of_birth = row[:date_of_birth]
            r.profile_extra = { phone: row[:phone] }
            r.deals_this_quarter = row[:deals_this_quarter]
            r.status = row[:status]
            r.satisfaction = row[:satisfaction]
            r.renewal_rate = row[:renewal_rate]
            r.avg_response_time_hours = row[:avg_response_time_hours]
            r.experience_years = row[:experience_years]
            r.revenue_managed = row[:revenue_managed]
            r.conversion_rate_pct = row[:conversion_rate_pct]
            r.referral_generated = row[:referral_generated]
            r.recommendations = row[:recommendations]
            r.reports = row[:reports]
            r.performance = row[:performance]
            r.activities = row[:activities]
            r.documents = row[:documents]
          end
        end
        puts "Seeded RAM members: #{App::Models::RamMember.count}"
      end

      # ---------------------------------------------------------------------
      # 12. Portfolio Members (frontend/lib/data/staff.js's portfolioMembers[])
      # ---------------------------------------------------------------------
      PORTFOLIO_MEMBERS = [
        { name: "Lakshmi Narayan", email: "lakshmi.n@rerockrealty.com", avatar: 9, clients_managed: 42, aum: 285_000_000, rating: 4.8, ram_mock_id: "ram1" },
        { name: "Farhan Ahmed", email: "farhan.a@rerockrealty.com", avatar: 15, clients_managed: 36, aum: 210_000_000, rating: 4.6, ram_mock_id: "ram2" },
        { name: "Ritu Choudhary", email: "ritu.c@rerockrealty.com", avatar: 29, clients_managed: 51, aum: 340_000_000, rating: 4.9, ram_mock_id: "ram3" },
      ].freeze

      def seed_portfolio_members!
        ram_email_by_mock_id = RAM_MEMBERS.each_with_object({}) { |r, h| h[r[:mock_id]] = r[:email] }

        PORTFOLIO_MEMBERS.each do |row|
          ram = App::Models::RamMember.first(email: ram_email_by_mock_id[row[:ram_mock_id]])
          warn "[seed_portfolio_members!] no RAM member found for mock id '#{row[:ram_mock_id]}' (member '#{row[:name]}')" if ram.nil?

          App::Models::PortfolioMember.find_or_create(email: row[:email]) do |m|
            m.name = row[:name]
            m.avatar = avatar_url(row[:avatar])
            m.clients_managed = row[:clients_managed]
            m.aum = row[:aum]
            m.rating = row[:rating]
            m.ram_member_id = ram&.id
          end
        end
        puts "Seeded portfolio members: #{App::Models::PortfolioMember.count}"
      end

      # ---------------------------------------------------------------------
      # 13. Leads (frontend/lib/data/leads.js) — no natural key, see the
      #    Phase 2 header note. property_slug/community_slug/area_slug are
      #    resolved via real DB lookups; agent_slug/ram_id are plain deferred
      #    strings, copied straight across.
      # ---------------------------------------------------------------------
      LEADS = [
        {
          mock_id: "LD-2101", client_name: "Karthik Iyer", client_phone: "+91 90140 22110",
          client_email: "karthik.iyer@example.com", avatar: 51,
          property_slug: "sobha-royal-crest-5bhk-villa", community_slug: "sobha-royal-crest", area_slug: "narsingi",
          budget: 52_000_000, source: "Website", priority: "High", status: "Site Visit",
          last_follow_up: "2026-07-15", next_follow_up: "2026-07-19", agent_slug: "rahul-sharma", ram_id: "ram2",
          timeline: [
            { date: "2026-07-08", event: "Lead created", note: "Enquired via website villa listing." },
            { date: "2026-07-10", event: "Contacted", note: "Discussed budget and villa preferences over call." },
            { date: "2026-07-15", event: "Qualified", note: "Confirmed funding in place, shortlisted Sobha Royal Crest." },
            { date: "2026-07-19", event: "Site visit scheduled", note: "Visit booked for Villa 44, 11:00 AM." },
          ],
        },
        {
          mock_id: "LD-2102", client_name: "Fatima Sheikh", client_phone: "+91 90220 44551",
          client_email: "fatima.sheikh@example.com", avatar: 29,
          property_slug: "narsingi-premium-open-plot", community_slug: "sobha-royal-crest", area_slug: "narsingi",
          budget: 18_500_000, source: "Instagram", priority: "High", status: "Negotiation",
          last_follow_up: "2026-07-16", next_follow_up: "2026-07-20", agent_slug: "rahul-sharma", ram_id: "ram2",
          timeline: [
            { date: "2026-07-01", event: "Lead created", note: "Instagram ad enquiry — open plots in Narsingi." },
            { date: "2026-07-04", event: "Contacted", note: "WhatsApp introduction and brochure shared." },
            { date: "2026-07-09", event: "Site visit completed", note: "Visited plot #22, liked corner-facing option." },
            { date: "2026-07-16", event: "Negotiation", note: "Requesting 3% discount on booking amount." },
          ],
        },
        {
          mock_id: "LD-2103", client_name: "Rohit Malhotra", client_phone: "+91 90330 66778",
          client_email: "rohit.malhotra@example.com", avatar: 15,
          property_slug: "gachibowli-logistics-warehouse", community_slug: "lodha-evergreen", area_slug: "gachibowli",
          budget: 42_000_000, source: "Referral", priority: "Medium", status: "Enquiry",
          last_follow_up: "2026-07-14", next_follow_up: "2026-07-21", agent_slug: "rahul-sharma", ram_id: "ram3",
          timeline: [
            { date: "2026-07-12", event: "Lead created", note: "Referred by Kiran Kumar Reddy." },
            { date: "2026-07-14", event: "Contacted", note: "Discussed warehouse specs and lease-back options." },
          ],
        },
        {
          mock_id: "LD-2104", client_name: "Naveen Chandra", client_phone: "+91 90440 88991",
          client_email: "naveen.chandra@example.com", avatar: 17,
          property_slug: "brigade-horizon-3bhk-tower-a", community_slug: "brigade-horizon", area_slug: "kokapet",
          budget: 12_800_000, source: "Website", priority: "Medium", status: "Closed",
          last_follow_up: "2026-06-28", next_follow_up: nil, agent_slug: "priya-reddy", ram_id: "ram1",
          timeline: [
            { date: "2026-06-02", event: "Lead created", note: "Enquired about Tower A availability." },
            { date: "2026-06-05", event: "Contacted", note: "Shared floor plans and pricing sheet." },
            { date: "2026-06-14", event: "Site visit completed", note: "Toured Tower A, 14th floor unit." },
            { date: "2026-06-22", event: "Negotiation", note: "Agreed on payment plan with builder." },
            { date: "2026-06-28", event: "Won", note: "Booking amount received. Agreement signed." },
          ],
        },
        {
          mock_id: "LD-2105", client_name: "Swathi Nair", client_phone: "+91 90550 11002",
          client_email: "swathi.nair@example.com", avatar: 44,
          property_slug: "prestige-lakeside-3bhk", community_slug: "prestige-lakeside", area_slug: "tellapur",
          budget: 16_800_000, source: "Walk-in", priority: "High", status: "Qualified Lead",
          last_follow_up: "2026-07-13", next_follow_up: "2026-07-22", agent_slug: "priya-reddy", ram_id: "ram1",
          timeline: [
            { date: "2026-07-06", event: "Lead created", note: "Walked into the Prestige Lakeside sales office." },
            { date: "2026-07-09", event: "Contacted", note: "Follow-up call, confirmed home-loan pre-approval." },
            { date: "2026-07-13", event: "Qualified", note: "Ready to visit — shortlisted 2 units." },
          ],
        },
        {
          mock_id: "LD-2106", client_name: "Imran Qureshi", client_phone: "+91 90660 33224",
          client_email: "imran.qureshi@example.com", avatar: 31,
          property_slug: "financial-district-grade-a-office", community_slug: "brigade-horizon", area_slug: "financial-district",
          budget: 28_500_000, source: "Referral", priority: "Low", status: "Lost",
          last_follow_up: "2026-06-20", next_follow_up: nil, agent_slug: "priya-reddy", ram_id: "ram2",
          timeline: [
            { date: "2026-06-01", event: "Lead created", note: "Referred by an existing commercial client." },
            { date: "2026-06-08", event: "Contacted", note: "Discussed Grade A office floor plates." },
            { date: "2026-06-20", event: "Lost", note: "Chose a competitor property closer to their HQ." },
          ],
        },
        {
          mock_id: "LD-2107", client_name: "Pooja Bhatt", client_phone: "+91 90770 55336",
          client_email: "pooja.bhatt@example.com", avatar: 48,
          property_slug: "kondapur-high-street-retail", community_slug: "my-home-avatar", area_slug: "kondapur",
          budget: 8_200_000, source: "Website", priority: "Medium", status: "Enquiry",
          last_follow_up: nil, next_follow_up: "2026-07-20", agent_slug: "arjun-varma", ram_id: "ram3",
          timeline: [{ date: "2026-07-17", event: "Lead created", note: "Enquired about retail frontage availability." }],
        },
        {
          mock_id: "LD-2108", client_name: "Aditya Rane", client_phone: "+91 90880 77448",
          client_email: "aditya.rane@example.com", avatar: 13,
          property_slug: "gachibowli-logistics-warehouse", community_slug: "lodha-evergreen", area_slug: "gachibowli",
          budget: 42_000_000, source: "Website", priority: "High", status: "Site Visit",
          last_follow_up: "2026-07-16", next_follow_up: "2026-07-18", agent_slug: "arjun-varma", ram_id: "ram3",
          timeline: [
            { date: "2026-07-10", event: "Lead created", note: "Logistics firm scouting warehouse space." },
            { date: "2026-07-13", event: "Contacted", note: "Site coordinates and dock-door specs shared." },
            { date: "2026-07-16", event: "Site visit scheduled", note: "Facilities team visiting tomorrow at 3 PM." },
          ],
        },
        {
          mock_id: "LD-2109", client_name: "Harini Suresh", client_phone: "+91 90990 99551",
          client_email: "harini.suresh@example.com", avatar: 43,
          property_slug: "aparna-zenon-2bhk", community_slug: "aparna-zenon", area_slug: "miyapur",
          budget: 6_800_000, source: "Instagram", priority: "Medium", status: "Enquiry",
          last_follow_up: "2026-07-12", next_follow_up: "2026-07-19", agent_slug: "arjun-varma", ram_id: "ram3",
          timeline: [
            { date: "2026-07-09", event: "Lead created", note: "Instagram enquiry — first-time buyer." },
            { date: "2026-07-12", event: "Contacted", note: "Explained EMI plans and possession timeline." },
          ],
        },
        {
          mock_id: "LD-2110", client_name: "Devansh Oberoi", client_phone: "+91 91001 22664",
          client_email: "devansh.oberoi@example.com", avatar: 16,
          property_slug: "aparna-zenon-2bhk", community_slug: "aparna-zenon", area_slug: "miyapur",
          budget: 7_200_000, source: "Referral", priority: "High", status: "Negotiation",
          last_follow_up: "2026-07-17", next_follow_up: "2026-07-20", agent_slug: "sneha-rao", ram_id: "ram3",
          timeline: [
            { date: "2026-06-30", event: "Lead created", note: "Referred by a colleague at Divya Prasad's office." },
            { date: "2026-07-05", event: "Contacted", note: "Shared unit options facing the central park." },
            { date: "2026-07-11", event: "Site visit completed", note: "Visited two 2 BHK units, preferred the corner unit." },
            { date: "2026-07-17", event: "Negotiation", note: "Negotiating on floor-rise charges." },
          ],
        },
        {
          mock_id: "LD-2111", client_name: "Lavanya Menon", client_phone: "+91 91002 44117",
          client_email: "lavanya.menon@example.com", avatar: 42,
          property_slug: "prestige-lakeside-3bhk", community_slug: "prestige-lakeside", area_slug: "tellapur",
          budget: 17_200_000, source: "Website", priority: "Medium", status: "Closed",
          last_follow_up: "2026-06-25", next_follow_up: nil, agent_slug: "sneha-rao", ram_id: "ram1",
          timeline: [
            { date: "2026-05-28", event: "Lead created", note: "Enquired about lake-facing units." },
            { date: "2026-06-02", event: "Contacted", note: "Shared pricing sheet and payment schedule." },
            { date: "2026-06-10", event: "Site visit completed", note: "Toured the show-flat, loved the lake view." },
            { date: "2026-06-18", event: "Negotiation", note: "Finalized floor and view premium." },
            { date: "2026-06-25", event: "Won", note: "Agreement signed, booking amount cleared." },
          ],
        },
        {
          mock_id: "LD-2112", client_name: "Yusuf Ali", client_phone: "+91 91003 66882",
          client_email: "yusuf.ali@example.com", avatar: 18,
          property_slug: "kondapur-high-street-retail", community_slug: "my-home-avatar", area_slug: "kondapur",
          budget: 8_500_000, source: "Walk-in", priority: "Low", status: "Enquiry",
          last_follow_up: nil, next_follow_up: "2026-07-21", agent_slug: "sneha-rao", ram_id: "ram2",
          timeline: [{ date: "2026-07-17", event: "Lead created", note: "Walked in asking about retail unit sizes." }],
        },
      ].freeze

      def seed_leads!
        if App::Models::Lead.count.positive?
          puts "Leads already seeded (#{App::Models::Lead.count} rows) — skipping (no natural key, see Phase 2 header note)."
          return
        end

        LEADS.each do |row|
          property = App::Models::Property.first(slug: row[:property_slug])
          community = App::Models::Community.first(slug: row[:community_slug])
          area = App::Models::Area.first(slug: row[:area_slug])

          App::Models::Lead.create do |l|
            l.client_name = row[:client_name]
            l.client_phone = row[:client_phone]
            l.client_email = row[:client_email]
            l.avatar = avatar_url(row[:avatar])
            l.property_id = property&.id
            l.community_id = community&.id
            l.area_id = area&.id
            l.budget = row[:budget]
            l.source = row[:source]
            l.priority = row[:priority]
            l.status = row[:status]
            l.last_follow_up = row[:last_follow_up]
            l.next_follow_up = row[:next_follow_up]
            l.agent_slug = row[:agent_slug]
            l.ram_id = row[:ram_id]
            l.timeline = row[:timeline]
          end
        end
        puts "Seeded leads: #{App::Models::Lead.count}"
      end

      # ---------------------------------------------------------------------
      # 14. Site Visits (frontend/lib/data/siteVisits.js) — no natural key,
      #    see the Phase 2 header note. lead_id is resolved via a
      #    mock lead id -> client_phone lookup table built from LEADS (Lead
      #    has no stored "code" column, so client_phone — unique per sample
      #    lead — stands in as the resolvable join key).
      # ---------------------------------------------------------------------
      SITE_VISITS = [
        { lead_mock_id: "LD-2101", client_name: "Karthik Iyer", property_slug: "sobha-royal-crest-5bhk-villa", community_slug: "sobha-royal-crest", agent_slug: "rahul-sharma", date: "2026-07-18", time: "11:00 AM", status: "Scheduled", notes: "" },
        { lead_mock_id: "LD-2102", client_name: "Fatima Sheikh", property_slug: "narsingi-premium-open-plot", community_slug: "sobha-royal-crest", agent_slug: "rahul-sharma", date: "2026-07-09", time: "4:00 PM", status: "Completed", notes: "Liked the corner-facing plot #22. Requested a 3% discount before booking." },
        { lead_mock_id: "LD-2103", client_name: "Rohit Malhotra", property_slug: "gachibowli-logistics-warehouse", community_slug: "lodha-evergreen", agent_slug: "rahul-sharma", date: "2026-07-24", time: "10:30 AM", status: "Scheduled", notes: "" },
        { lead_mock_id: "LD-2104", client_name: "Naveen Chandra", property_slug: "brigade-horizon-3bhk-tower-a", community_slug: "brigade-horizon", agent_slug: "priya-reddy", date: "2026-06-14", time: "3:00 PM", status: "Completed", notes: "Toured the 14th floor unit, loved the skyline view. Proceeded to negotiation." },
        { lead_mock_id: "LD-2105", client_name: "Swathi Nair", property_slug: "prestige-lakeside-3bhk", community_slug: "prestige-lakeside", agent_slug: "priya-reddy", date: "2026-07-22", time: "5:00 PM", status: "Scheduled", notes: "" },
        { lead_mock_id: "LD-2106", client_name: "Imran Qureshi", property_slug: "financial-district-grade-a-office", community_slug: "brigade-horizon", agent_slug: "priya-reddy", date: "2026-06-15", time: "1:00 PM", status: "Cancelled", notes: "Client rescheduled twice, then went with a competitor property." },
        { lead_mock_id: "LD-2108", client_name: "Aditya Rane", property_slug: "gachibowli-logistics-warehouse", community_slug: "lodha-evergreen", agent_slug: "arjun-varma", date: "2026-07-18", time: "3:00 PM", status: "Scheduled", notes: "" },
        { lead_mock_id: "LD-2109", client_name: "Harini Suresh", property_slug: "aparna-zenon-2bhk", community_slug: "aparna-zenon", agent_slug: "arjun-varma", date: "2026-07-13", time: "11:30 AM", status: "Rescheduled", notes: "Client asked to move from the 12th to the 19th, waiting on confirmation." },
        { lead_mock_id: "LD-2110", client_name: "Devansh Oberoi", property_slug: "aparna-zenon-2bhk", community_slug: "aparna-zenon", agent_slug: "sneha-rao", date: "2026-07-11", time: "10:00 AM", status: "Completed", notes: "Visited two 2 BHK units, preferred the corner unit facing the park." },
        { lead_mock_id: "LD-2111", client_name: "Lavanya Menon", property_slug: "prestige-lakeside-3bhk", community_slug: "prestige-lakeside", agent_slug: "sneha-rao", date: "2026-06-10", time: "2:00 PM", status: "Completed", notes: "Toured the show-flat, loved the lake view — proceeded to booking." },
        { lead_mock_id: "LD-2112", client_name: "Yusuf Ali", property_slug: "kondapur-high-street-retail", community_slug: "my-home-avatar", agent_slug: "sneha-rao", date: "2026-07-18", time: "1:30 PM", status: "Scheduled", notes: "" },
        { lead_mock_id: "LD-2107", client_name: "Pooja Bhatt", property_slug: "kondapur-high-street-retail", community_slug: "my-home-avatar", agent_slug: "arjun-varma", date: "2026-07-20", time: "12:00 PM", status: "Scheduled", notes: "" },
      ].freeze

      def seed_site_visits!
        if App::Models::SiteVisit.count.positive?
          puts "Site visits already seeded (#{App::Models::SiteVisit.count} rows) — skipping (no natural key, see Phase 2 header note)."
          return
        end

        lead_phone_by_mock_id = LEADS.each_with_object({}) { |l, h| h[l[:mock_id]] = l[:client_phone] }

        SITE_VISITS.each do |row|
          lead = App::Models::Lead.first(client_phone: lead_phone_by_mock_id[row[:lead_mock_id]])
          property = App::Models::Property.first(slug: row[:property_slug])
          community = App::Models::Community.first(slug: row[:community_slug])

          App::Models::SiteVisit.create do |v|
            v.lead_id = lead&.id
            v.property_id = property&.id
            v.community_id = community&.id
            v.client_name = row[:client_name]
            v.agent_slug = row[:agent_slug]
            v.date = row[:date]
            v.time = row[:time]
            v.status = row[:status]
            v.notes = row[:notes]
          end
        end
        puts "Seeded site visits: #{App::Models::SiteVisit.count}"
      end

      # ---------------------------------------------------------------------
      # 15. Referrals (frontend/lib/data/referrals.js) — no natural key, see
      #    the Phase 2 header note. ram_id is a plain deferred string (RAM
      #    Network's own ids from the mock, e.g. "ram2") — copied straight
      #    across, no lookup needed (matches migrations/0016's own comment).
      # ---------------------------------------------------------------------
      REFERRALS = [
        { ram_id: "ram2", type: "Client Referral", referrer: "Kiran Kumar Reddy", referred: "Ananya Krishnan", status: "Purchase Completed", reward: 75_000, date: "2026-05-12" },
        { ram_id: "ram2", type: "Client Referral", referrer: "Kiran Kumar Reddy", referred: "Rohit Malhotra", status: "Site Visit Scheduled", reward: 0, date: "2026-06-20" },
        { ram_id: "ram2", type: "Agent Referral", referrer: "Priya Reddy (Agent)", referred: "Naveen Chandra", status: "Purchase Completed", reward: 25_000, date: "2026-06-28" },
        { ram_id: "ram1", type: "Client Referral", referrer: "Vikram Malhotra", referred: "Rakesh Bhalla", status: "Enquiry Stage", reward: 0, date: "2026-07-01" },
        { ram_id: "ram1", type: "Client Referral", referrer: "Meenal Deshpande", referred: "Sunita Verma", status: "Purchase Completed", reward: 45_000, date: "2026-03-02" },
        { ram_id: "ram3", type: "Client Referral", referrer: "Srinivas Rao", referred: "Ganesh Iyer", status: "Purchase Completed", reward: 60_000, date: "2026-04-18" },
        { ram_id: "ram3", type: "Agent Referral", referrer: "Sneha Rao (Agent)", referred: "Lavanya Menon", status: "Purchase Completed", reward: 30_000, date: "2026-06-25" },
      ].freeze

      def seed_referrals!
        if App::Models::Referral.count.positive?
          puts "Referrals already seeded (#{App::Models::Referral.count} rows) — skipping (no natural key, see Phase 2 header note)."
          return
        end

        REFERRALS.each do |row|
          App::Models::Referral.create do |r|
            r.ram_id = row[:ram_id]
            r.type = row[:type]
            r.referrer = row[:referrer]
            r.referred = row[:referred]
            r.status = row[:status]
            r.reward = row[:reward]
            r.date = row[:date]
          end
        end
        puts "Seeded referrals: #{App::Models::Referral.count}"
      end

      # ---------------------------------------------------------------------
      # 16. Clients (frontend/lib/data/clients.js) — extends the existing
      #    `clients` table (migrations/0017). Has a real natural key (email,
      #    unique), so this uses the same find_or_create idiom as Phase 1.
      #
      #    referred_by_id (self-referential FK) is resolved in two passes:
      #    pass 1 creates every client row (without referred_by_id); pass 2
      #    walks CLIENTS again and sets referred_by_id via a mock_id -> email
      #    lookup table, once every referenced row is guaranteed to exist.
      #
      #    invested_properties: each mock entry's `slug` is resolved to a real
      #    Property id (`propertyId`) via resolve_invested_properties below,
      #    matching migrations/0017's own comment that these jsonb entries
      #    should keep `propertyId` (+ `slug`) rather than just a bare name.
      # ---------------------------------------------------------------------
      CLIENTS = [
        {
          mock_id: "c1", name: "Kiran Kumar Reddy", email: "kiran.reddy@example.com", phone: "+91 98480 55210", avatar: 23,
          joined: "2022-03-14", status: "Active", assigned_agent_slug: "priya-reddy", assigned_ram_id: "ram2",
          type: "Individual", city: "Hyderabad", referral_source: "Website", referred_by_mock_id: nil,
          invested_properties: [
            { slug: "sobha-royal-crest-5bhk-villa", name: "Sobha Royal Crest — Villa 42", purchase_price: 42_000_000, current_value: 52_000_000, purchase_date: "2022-11-05" },
            { slug: "brigade-horizon-3bhk-tower-a", name: "Brigade Horizon — Tower A, 3 BHK", purchase_price: 11_200_000, current_value: 12_400_000, purchase_date: "2024-03-12" },
            { slug: "financial-district-grade-a-office", name: "Financial District — Grade A Office", purchase_price: 22_000_000, current_value: 28_500_000, purchase_date: "2021-07-20" },
            { slug: "aparna-zenon-2bhk", name: "Aparna Zenon — 2 BHK", purchase_price: 5_800_000, current_value: 6_800_000, purchase_date: "2023-01-30" },
          ],
          notes: [{ author: "Priya Reddy", text: "Prefers WhatsApp updates over calls. Interested in a 5th unit in Kokapet.", date: "2026-07-10" }],
          communication_log: [
            { type: "Call", note: "Discussed Q3 pricing revision at Brigade Horizon.", date: "2026-07-14" },
            { type: "WhatsApp", note: "Shared floor plans for the new Kokapet phase.", date: "2026-07-05" },
          ],
          timeline: [
            { title: "Purchased Aparna Zenon — 2 BHK", time: "2023-01-30", done: true },
            { title: "Purchased Financial District Office", time: "2021-07-20", done: true },
            { title: "Purchased Brigade Horizon — Tower A", time: "2024-03-12", done: true },
            { title: "Purchased Sobha Royal Crest — Villa 42", time: "2022-11-05", done: true },
          ],
        },
        {
          mock_id: "c2", name: "Ayesha Khan", email: "ayesha.khan@example.com", phone: "+91 90003 11224", avatar: 32,
          joined: "2024-01-20", status: "Active", assigned_agent_slug: "sneha-rao", assigned_ram_id: "ram2",
          type: "Individual", city: "Hyderabad", referral_source: "Instagram", referred_by_mock_id: nil,
          invested_properties: [{ slug: "brigade-horizon-3bhk-tower-a", name: "Brigade Horizon — Penthouse", purchase_price: 11_500_000, current_value: 12_400_000, purchase_date: "2024-01-20" }],
          notes: [{ author: "Sneha Rao", text: "First-time investor, values transparent documentation.", date: "2026-06-20" }],
          communication_log: [{ type: "Email", note: "Sent registration completion confirmation.", date: "2024-02-02" }],
          timeline: [{ title: "Purchased Brigade Horizon — Penthouse", time: "2024-01-20", done: true }],
        },
        {
          mock_id: "c3", name: "Vikram Malhotra", email: "vikram.m@example.com", phone: "+91 91000 44556", avatar: 52,
          joined: "2021-07-09", status: "Active", assigned_agent_slug: "rahul-sharma", assigned_ram_id: "ram1",
          type: "NRI", city: "Dubai", referral_source: "Referral", referred_by_mock_id: "c1",
          invested_properties: [
            { slug: "sobha-royal-crest-5bhk-villa", name: "Sobha Royal Crest — Villa 18", purchase_price: 24_000_000, current_value: 27_500_000, purchase_date: "2021-07-09" },
            { slug: "prestige-lakeside-3bhk", name: "Prestige Lakeside — 3 BHK", purchase_price: 11_800_000, current_value: 13_000_000, purchase_date: "2023-05-14" },
          ],
          notes: [{ author: "Rahul Sharma", text: "NRI client — coordinates payments via POA. Prefers evening IST calls.", date: "2026-06-28" }],
          communication_log: [{ type: "Call", note: "Portfolio review call, satisfied with appreciation.", date: "2026-06-28" }],
          timeline: [
            { title: "Purchased Sobha Royal Crest — Villa 18", time: "2021-07-09", done: true },
            { title: "Purchased Prestige Lakeside — 3 BHK", time: "2023-05-14", done: true },
          ],
        },
        {
          mock_id: "c4", name: "Meenal Deshpande", email: "meenal.d@example.com", phone: "+91 98490 33110", avatar: 28,
          joined: "2023-01-30", status: "Active", assigned_agent_slug: "priya-reddy", assigned_ram_id: "ram1",
          type: "Individual", city: "Hyderabad", referral_source: "Website", referred_by_mock_id: nil,
          invested_properties: [{ slug: "aparna-zenon-2bhk", name: "Aparna Zenon — 2 BHK", purchase_price: 5_800_000, current_value: 6_800_000, purchase_date: "2023-01-30" }],
          notes: [{ author: "Priya Reddy", text: "First-time buyer — walked through every document in detail before signing.", date: "2023-01-28" }],
          communication_log: [{ type: "Meeting", note: "In-person walkthrough of the sale agreement.", date: "2023-01-28" }],
          timeline: [{ title: "Purchased Aparna Zenon — 2 BHK", time: "2023-01-30", done: true }],
        },
        {
          mock_id: "c5", name: "Srinivas Rao", email: "srinivas.rao@example.com", phone: "+91 99000 22114", avatar: 19,
          joined: "2020-11-12", status: "Inactive", assigned_agent_slug: "arjun-varma", assigned_ram_id: "ram3",
          type: "Company", city: "Hyderabad", referral_source: "Walk-in", referred_by_mock_id: nil,
          invested_properties: [{ slug: "financial-district-grade-a-office", name: "Financial District — Grade A Office", purchase_price: 36_000_000, current_value: 42_000_000, purchase_date: "2020-11-12" }],
          notes: [{ author: "Arjun Varma", text: "Commercial investor, has gone quiet since last renewal — flagged inactive.", date: "2026-04-02" }],
          communication_log: [{ type: "Email", note: "Sent lease renewal reminder, no response.", date: "2026-04-02" }],
          timeline: [{ title: "Purchased Financial District Office", time: "2020-11-12", done: true }],
        },
        {
          mock_id: "c6", name: "Divya Prasad", email: "divya.p@example.com", phone: "+91 90100 88221", avatar: 28,
          joined: "2025-06-01", status: "Active", assigned_agent_slug: "rahul-sharma", assigned_ram_id: "ram3",
          type: "Individual", city: "Hyderabad", referral_source: "Referral", referred_by_mock_id: "c3",
          invested_properties: [{ slug: "kondapur-high-street-retail", name: "Kondapur High-Street Retail", purchase_price: 15_200_000, current_value: 16_800_000, purchase_date: "2025-06-01" }],
          notes: [{ author: "Rahul Sharma", text: "Referred by Vikram Malhotra — interested in a second retail unit next year.", date: "2025-06-05" }],
          communication_log: [{ type: "Call", note: "Onboarding call, walked through portfolio dashboard.", date: "2025-06-05" }],
          timeline: [{ title: "Purchased Kondapur High-Street Retail", time: "2025-06-01", done: true }],
        },
      ].freeze

      def resolve_invested_properties(entries)
        entries.map do |entry|
          property = App::Models::Property.first(slug: entry[:slug])
          {
            propertyId: property&.id,
            slug: entry[:slug],
            name: entry[:name],
            purchasePrice: entry[:purchase_price],
            currentValue: entry[:current_value],
            purchaseDate: entry[:purchase_date],
          }
        end
      end

      def seed_clients!
        CLIENTS.each do |row|
          App::Models::Client.find_or_create(email: row[:email]) do |c|
            c.name = row[:name]
            c.phone = row[:phone]
            c.avatar = avatar_url(row[:avatar])
            c.joined = row[:joined]
            c.status = row[:status]
            c.assigned_agent_slug = row[:assigned_agent_slug]
            c.assigned_ram_id = row[:assigned_ram_id]
            c.type = row[:type]
            c.city = row[:city]
            c.referral_source = row[:referral_source]
            c.invested_properties = resolve_invested_properties(row[:invested_properties])
            c.notes = row[:notes]
            c.communication_log = row[:communication_log]
            c.timeline = row[:timeline]
          end
        end

        # Pass 2: every client row now definitely exists, so resolve the
        # self-referential referred_by_id via a mock_id -> email lookup table.
        email_by_mock_id = CLIENTS.each_with_object({}) { |r, h| h[r[:mock_id]] = r[:email] }
        CLIENTS.each do |row|
          next if row[:referred_by_mock_id].nil?

          client = App::Models::Client.first(email: row[:email])
          referrer = App::Models::Client.first(email: email_by_mock_id[row[:referred_by_mock_id]])
          if client.nil? || referrer.nil?
            warn "[seed_clients!] could not link '#{row[:mock_id]}' -> referrer '#{row[:referred_by_mock_id]}'"
            next
          end
          client.update(referred_by_id: referrer.id)
        end

        puts "Seeded clients: #{App::Models::Client.count}"
      end

      # ---------------------------------------------------------------------
      # 17. Deals (frontend/lib/data/deals.js) — no natural key, see the
      #    Phase 2 header note. client_id resolves against the now-real
      #    Clients table by name (nil when the deal's clientName is a
      #    Leads-only prospect with no formal Client record yet — expected,
      #    matches migrations/0018's own "deal can predate a full Client
      #    record" reasoning). property_id is deliberately left nil for every
      #    row: the mock's propertyName strings are specific-unit display
      #    text ("Sobha Royal Crest — Villa 44") that doesn't reliably map
      #    1:1 onto a single seeded Properties row (a community here may back
      #    several Property records, none of which is "Villa 44" specifically)
      #    — same ambiguity migrations/0018's own comment calls out, so
      #    property_name alone carries the fallback display string as
      #    designed.
      # ---------------------------------------------------------------------
      DEALS = [
        { client_name: "Karthik Iyer", agent_slug: "rahul-sharma", property_name: "Sobha Royal Crest — Villa 44", value: 52_000_000, probability: 35, stage: "Opportunity", closing_date: "2026-09-12" },
        { client_name: "Fatima Sheikh", agent_slug: "rahul-sharma", property_name: "Narsingi Premium Open Plot", value: 18_500_000, probability: 60, stage: "Negotiation", closing_date: "2026-08-10" },
        { client_name: "Vikram Malhotra", agent_slug: "rahul-sharma", property_name: "Prestige Lakeside — 3 BHK", value: 13_000_000, probability: 100, stage: "Closed", closing_date: "2023-05-14" },
        { client_name: "Naveen Chandra", agent_slug: "priya-reddy", property_name: "Brigade Horizon — Tower A", value: 12_800_000, probability: 85, stage: "Booking", closing_date: "2026-06-28" },
        { client_name: "Swathi Nair", agent_slug: "priya-reddy", property_name: "Prestige Lakeside — 3 BHK", value: 16_800_000, probability: 55, stage: "Proposal", closing_date: "2026-08-20" },
        { client_name: "Kiran Kumar Reddy", agent_slug: "priya-reddy", property_name: "Brigade Horizon — Tower A, 3 BHK", value: 11_200_000, probability: 100, stage: "Closed", closing_date: "2024-03-12" },
        { client_name: "Pooja Bhatt", agent_slug: "arjun-varma", property_name: "Kondapur High-Street Retail", value: 8_200_000, probability: 25, stage: "Opportunity", closing_date: "2026-09-20" },
        { client_name: "Aditya Rane", agent_slug: "arjun-varma", property_name: "Gachibowli Logistics Warehouse", value: 42_000_000, probability: 70, stage: "Negotiation", closing_date: "2026-08-02" },
        { client_name: "Srinivas Rao", agent_slug: "arjun-varma", property_name: "Financial District — Grade A Office", value: 36_000_000, probability: 100, stage: "Closed", closing_date: "2020-11-12" },
        { client_name: "Devansh Oberoi", agent_slug: "sneha-rao", property_name: "Aparna Zenon — 2 BHK", value: 7_200_000, probability: 45, stage: "Proposal", closing_date: "2026-08-15" },
        { client_name: "Lavanya Menon", agent_slug: "sneha-rao", property_name: "Prestige Lakeside — 3 BHK", value: 17_200_000, probability: 90, stage: "Booking", closing_date: "2026-06-25" },
        { client_name: "Ayesha Khan", agent_slug: "sneha-rao", property_name: "Brigade Horizon — Penthouse", value: 11_500_000, probability: 100, stage: "Closed", closing_date: "2024-01-20" },
      ].freeze

      def seed_deals!
        if App::Models::Deal.count.positive?
          puts "Deals already seeded (#{App::Models::Deal.count} rows) — skipping (no natural key, see Phase 2 header note)."
          return
        end

        DEALS.each do |row|
          client = App::Models::Client.first(name: row[:client_name])

          App::Models::Deal.create do |d|
            d.client_id = client&.id
            d.client_name = row[:client_name]
            d.property_id = nil
            d.property_name = row[:property_name]
            d.agent_slug = row[:agent_slug]
            d.value = row[:value]
            d.probability = row[:probability]
            d.stage = row[:stage]
            d.closing_date = row[:closing_date]
          end
        end
        puts "Seeded deals: #{App::Models::Deal.count}"
      end

      # =======================================================================
      # PHASE 3 (FINAL): Finance (Expenses, Invoices, Payments, Refunds,
      # Taxes), Marketing/CMS (Blogs, Testimonials, FAQs, Job Openings,
      # Career Benefits, SEO Pages, Hero Stats, Homepage Settings), and
      # Ops/Logs (Notifications, Media Items). Once this phase runs, every
      # resource across the entire roadmap has real sample data — Activity
      # Logs/Audit Logs are the only two resources deliberately left
      # unseeded (system-generated, per the task).
      #
      # Idempotency — same two strategies as Phase 1/2, applied per resource:
      # - Blogs (`slug`) and SEO Pages (`route`) have real unique columns in
      #   their migrations (0027/0032) — find_or_create(natural_key), same
      #   idiom as every Phase 1/2 resource with a real slug/email/route.
      # - Expenses, Invoices, Payments, Refunds, Taxes, Testimonials, FAQs,
      #   Job Openings, Career Benefits, Hero Stats, Notifications, and Media
      #   Items have no natural key in EITHER the mock sample data or the
      #   real migration (no slug/email/route-like unique column) — each is
      #   guarded with `return if Model.count.positive?` and uses plain
      #   Model.create per row, same as Leads/Site Visits/Referrals/Deals in
      #   Phase 2. (Expenses/Refunds do carry mock string ids like "EXP-001"/
      #   "REF-001", but neither migrations/0022 nor migrations/0025 has a
      #   column to store them against — so the count-guard here isn't a
      #   stylistic choice, it's the only option.)
      # - Homepage Settings is the one true singleton — seeded with a plain
      #   "row exists? skip : create it" check, matching
      #   services/homepage_settings.rb's own `model.first || model.create`
      #   lazy-singleton pattern exactly.
      #
      # Invoices/Payments/Taxes are NOT transcribed from any finance.js
      # sample array — that file has no standalone arrays for them (see its
      # own header comment: "commission, revenue, invoices, payments and tax
      # ... roll up from the same closed-deal records"). Since Deals is now
      # real (Phase 2), these three instead query
      # `App::Models::Deal.where(stage: "Closed")` directly and regenerate
      # the same shape finance.js's getInvoices()/getPayments()/
      # getTaxRecords() computed on the fly at render time: one invoice, a
      # 20%/80% booking-advance + final-payment split, and one GST + one
      # Stamp Duty record per closed deal — with deal_id/client_id resolved
      # straight off each real seeded Deal row (client_id may be nil for a
      # Leads-only prospect with no formal Client record yet, exactly like
      # Deal#client_id itself already can be — see seed_deals! above).
      # =======================================================================

      # ---------------------------------------------------------------------
      # 18. Expenses (frontend/lib/data/finance.js) — a standalone
      #    operating-cost ledger with no upstream mock source table (unlike
      #    Invoices/Payments/Taxes below, which the mock derived from closed
      #    Deals). No natural key — count-guard, see Phase 3 header note.
      # ---------------------------------------------------------------------
      EXPENSES = [
        { category: "Staff Salaries", description: "July payroll — Hyderabad office", amount: 4_200_000, month: "Jul 2026", approved_by: "Lakshmi Narayan" },
        { category: "Office Rent", description: "Financial District HQ — monthly lease", amount: 850_000, month: "Jul 2026", approved_by: "Farhan Ahmed" },
        { category: "Marketing", description: "Sobha Royal Crest launch campaign", amount: 620_000, month: "Jul 2026", approved_by: "Ritu Choudhary" },
        { category: "Technology", description: "CRM + property listing platform renewal", amount: 180_000, month: "Jul 2026", approved_by: "Lakshmi Narayan" },
        { category: "Legal & Compliance", description: "RERA filing fees — Q2 projects", amount: 240_000, month: "Jul 2026", approved_by: "Farhan Ahmed" },
        { category: "Sales Commission Payout", description: "June commission settlement — all agents", amount: 1_520_000, month: "Jun 2026", approved_by: "Lakshmi Narayan" },
        { category: "Marketing", description: "Digital ads — Instagram & Google", amount: 340_000, month: "Jun 2026", approved_by: "Ritu Choudhary" },
        { category: "Staff Salaries", description: "June payroll — Hyderabad office", amount: 4_150_000, month: "Jun 2026", approved_by: "Lakshmi Narayan" },
        { category: "Office Rent", description: "Financial District HQ — monthly lease", amount: 850_000, month: "Jun 2026", approved_by: "Farhan Ahmed" },
        { category: "Technology", description: "Cloud hosting & backups", amount: 96_000, month: "Jun 2026", approved_by: "Ritu Choudhary" },
        { category: "Legal & Compliance", description: "Retainer — corporate counsel", amount: 150_000, month: "May 2026", approved_by: "Farhan Ahmed" },
        { category: "Marketing", description: "Print & hoarding — Kokapet corridor", amount: 275_000, month: "May 2026", approved_by: "Ritu Choudhary" },
        { category: "Staff Salaries", description: "May payroll — Hyderabad office", amount: 4_080_000, month: "May 2026", approved_by: "Lakshmi Narayan" },
        { category: "Sales Commission Payout", description: "May commission settlement — all agents", amount: 1_380_000, month: "May 2026", approved_by: "Lakshmi Narayan" },
      ].freeze

      def seed_expenses!
        if App::Models::Expense.count.positive?
          puts "Expenses already seeded (#{App::Models::Expense.count} rows) — skipping (no natural key, see Phase 3 header note)."
          return
        end

        EXPENSES.each do |row|
          App::Models::Expense.create do |e|
            e.category = row[:category]
            e.description = row[:description]
            e.amount = row[:amount]
            e.month = row[:month]
            e.approved_by = row[:approved_by]
          end
        end
        puts "Seeded expenses: #{App::Models::Expense.count}"
      end

      # ---------------------------------------------------------------------
      # Shared helpers for Invoices/Payments/Taxes (19-22 below) — mirror
      # lib/data/finance.js's own `closedDeals()`/`addDays()`/`monthLabel()`
      # helpers, but query the real Deals table instead of filtering a JS
      # array. `.to_s` on the date arg handles both a real Sequel Date
      # column value and a plain seeded String equally.
      # ---------------------------------------------------------------------
      def closed_deals
        App::Models::Deal.where(stage: "Closed").all
      end

      def add_days(date_val, days)
        (Date.parse(date_val.to_s) + days).to_s
      end

      def month_label(date_val)
        Date.parse(date_val.to_s).strftime("%b %Y")
      end

      # ---------------------------------------------------------------------
      # 19. Invoices (frontend/lib/data/finance.js#getInvoices) — one per
      #    closed Deal, see the shared header note above. No natural key —
      #    count-guard.
      # ---------------------------------------------------------------------
      INVOICE_STATUSES = ["Paid", "Partially Paid", "Unpaid"].freeze

      def seed_invoices!
        if App::Models::Invoice.count.positive?
          puts "Invoices already seeded (#{App::Models::Invoice.count} rows) — skipping (no natural key, see Phase 3 header note)."
          return
        end

        closed_deals.each_with_index do |deal, i|
          App::Models::Invoice.create do |inv|
            inv.deal_id = deal.id
            inv.client_id = deal.client_id
            inv.client_name = deal.client_name
            inv.property_name = deal.property_name
            inv.agent_slug = deal.agent_slug
            inv.amount = deal.value
            inv.status = INVOICE_STATUSES[i % INVOICE_STATUSES.length]
            inv.issued_date = deal.closing_date
            inv.due_date = add_days(deal.closing_date, 30)
          end
        end
        puts "Seeded invoices: #{App::Models::Invoice.count}"
      end

      # ---------------------------------------------------------------------
      # 20. Payments (frontend/lib/data/finance.js#getPayments) — a
      #    booking-advance (20%) + final-payment (80%) installment per
      #    closed Deal. No natural key — count-guard.
      # ---------------------------------------------------------------------
      PAYMENT_MODES = ["Bank Transfer", "UPI", "Cheque", "Net Banking"].freeze

      def seed_payments!
        if App::Models::Payment.count.positive?
          puts "Payments already seeded (#{App::Models::Payment.count} rows) — skipping (no natural key, see Phase 3 header note)."
          return
        end

        closed_deals.each_with_index do |deal, i|
          advance = (deal.value * 0.2).round

          App::Models::Payment.create do |pmt|
            pmt.deal_id = deal.id
            pmt.client_id = deal.client_id
            pmt.client_name = deal.client_name
            pmt.milestone = "Booking Advance"
            pmt.amount = advance
            pmt.mode = PAYMENT_MODES[i % PAYMENT_MODES.length]
            pmt.paid_date = deal.closing_date
          end

          App::Models::Payment.create do |pmt|
            pmt.deal_id = deal.id
            pmt.client_id = deal.client_id
            pmt.client_name = deal.client_name
            pmt.milestone = "Final Payment"
            pmt.amount = deal.value - advance
            pmt.mode = PAYMENT_MODES[(i + 1) % PAYMENT_MODES.length]
            pmt.paid_date = add_days(deal.closing_date, 14)
          end
        end
        puts "Seeded payments: #{App::Models::Payment.count}"
      end

      # ---------------------------------------------------------------------
      # 21. Refunds (frontend/lib/data/finance.js) — like Expenses, a
      #    standalone dataset never derived from Deals (no "cancelled" deal
      #    stage exists to derive from). client_id resolves against the real
      #    seeded Clients table by name; property_id is deliberately left
      #    nil for every row, same reasoning as Deal#property_id
      #    (migrations/0018's own comment / seed_deals! above) — each
      #    propertyName here is a specific-unit display string ("Aparna
      #    Zenon — 1 BHK") that doesn't reliably map onto a single seeded
      #    Property row, so property_name alone carries the fallback
      #    display text. No natural key — count-guard.
      # ---------------------------------------------------------------------
      REFUNDS = [
        { client_name: "Meenal Deshpande", property_name: "Aparna Zenon — 1 BHK", amount: 350_000, reason: "Changed investment preference", status: "Processed", requested_date: "2026-05-02" },
        { client_name: "Aditya Rane", property_name: "Gachibowli Logistics Warehouse — Unit 3", amount: 1_200_000, reason: "Financing fell through", status: "Requested", requested_date: "2026-07-11" },
        { client_name: "Devansh Oberoi", property_name: "Aparna Zenon — 2 BHK", amount: 500_000, reason: "Duplicate booking advance", status: "Processed", requested_date: "2026-04-18" },
        { client_name: "Pooja Bhatt", property_name: "Kondapur High-Street Retail — Unit 2", amount: 420_000, reason: "Site plan mismatch on inspection", status: "Rejected", requested_date: "2026-06-25" },
      ].freeze

      def seed_refunds!
        if App::Models::Refund.count.positive?
          puts "Refunds already seeded (#{App::Models::Refund.count} rows) — skipping (no natural key, see Phase 3 header note)."
          return
        end

        REFUNDS.each do |row|
          client = App::Models::Client.first(name: row[:client_name])

          App::Models::Refund.create do |r|
            r.client_id = client&.id
            r.property_id = nil
            r.client_name = row[:client_name]
            r.property_name = row[:property_name]
            r.amount = row[:amount]
            r.reason = row[:reason]
            r.status = row[:status]
            r.requested_date = row[:requested_date]
          end
        end
        puts "Seeded refunds: #{App::Models::Refund.count}"
      end

      # ---------------------------------------------------------------------
      # 22. Taxes (frontend/lib/data/finance.js#getTaxRecords) — one GST +
      #    one Stamp Duty filing per closed Deal. No natural key —
      #    count-guard.
      # ---------------------------------------------------------------------
      TAX_TYPES = ["GST", "Stamp Duty"].freeze
      TAX_STATUSES = ["Filed", "Pending", "Overdue"].freeze
      TAX_RATE_PCT = { "GST" => 5, "Stamp Duty" => 6 }.freeze

      def seed_taxes!
        if App::Models::Tax.count.positive?
          puts "Taxes already seeded (#{App::Models::Tax.count} rows) — skipping (no natural key, see Phase 3 header note)."
          return
        end

        closed_deals.each_with_index do |deal, i|
          TAX_TYPES.each_with_index do |type, j|
            App::Models::Tax.create do |t|
              t.deal_id = deal.id
              t.type = type
              t.amount = (deal.value * TAX_RATE_PCT[type] / 100.0).round
              t.period = month_label(deal.closing_date)
              t.status = TAX_STATUSES[(i + j) % TAX_STATUSES.length]
            end
          end
        end
        puts "Seeded taxes: #{App::Models::Tax.count}"
      end

      # ---------------------------------------------------------------------
      # 23. Blogs (frontend/lib/data/blogs.js) — real unique `slug`
      #    (migrations/0027) — find_or_create, same idiom as Phase 1/2.
      # ---------------------------------------------------------------------
      BLOGS = [
        {
          slug: "kokapet-investment-outlook-2026",
          title: "Kokapet 2026 Outlook: Why Investors Are Doubling Down",
          excerpt: "A deep dive into infrastructure triggers, absorption rates, and why Kokapet continues to outperform every other Hyderabad micro-market.",
          image: :skyline_aerial_1, category: "Market Insight", date: "2026-06-02", read_time: "6 min read",
          author_name: "Sneha Rao", author_role: "Client Relationship Manager", author_avatar: 45,
          content: [
            "Kokapet has quietly become Hyderabad's most-watched micro-market, and the numbers back the noise. Price per square foot has grown 22% year-on-year, outpacing every other corridor we track, driven almost entirely by proximity to the Financial District and a wave of Grade-A commercial completions.",
            "What's different this cycle is absorption velocity. Units that took 18 months to sell out in 2022 are now moving in under six, and that compression is visible across both under-construction and ready-to-move inventory.",
            "The infrastructure triggers are real: the proposed metro extension, the Outer Ring Road upgrade, and three new international schools opening within the next 24 months. None of these are speculative — all three are funded and under active construction as of this writing.",
            "Our view: Kokapet's growth curve still has 3-4 years of runway before it matures into a Gachibowli-style plateau. For investors with a 5-7 year horizon, this remains the highest-conviction corridor in our coverage.",
          ],
        },
        {
          slug: "villa-vs-apartment-2026",
          title: "Villa vs. Apartment: What Actually Delivers Better ROI in 2026",
          excerpt: "We compared five-year appreciation and rental yield across 40 gated communities. The results challenge conventional wisdom.",
          image: :villa_exterior_1, category: "Investment Strategy", date: "2026-05-18", read_time: "8 min read",
          author_name: "Arjun Varma", author_role: "Commercial & Plots Specialist", author_avatar: 14,
          content: [
            "The conventional wisdom says villas appreciate faster than apartments because land value compounds while built structures depreciate. Across our sample of 40 gated communities, that held true — but only barely, and only past the seven-year mark.",
            "In the first five years, apartments in well-located, RERA-approved towers actually outperformed villas on a percentage basis, largely because entry prices are lower and rental yields are meaningfully higher — 3.2% average versus 1.8% for villas in the same corridors.",
            "Villas win decisively on absolute appreciation for holding periods beyond seven years, and on lifestyle premium — resale villas in mature communities like Sobha Royal Crest command a 15-20% premium purely on land scarcity.",
            "Our recommendation is horizon-dependent: apartments for a 3-6 year investment thesis, villas for a decade-plus hold or end-use purchase.",
          ],
        },
        {
          slug: "rera-checklist-for-buyers",
          title: "The Complete RERA Checklist Before You Sign",
          excerpt: "Every document, approval, and clause you should verify before making your next real estate investment.",
          image: :blueprint_1, category: "Buyer's Guide", date: "2026-04-29", read_time: "5 min read",
          author_name: "Priya Reddy", author_role: "Investment Advisor", author_avatar: 47,
          content: [
            "Before you sign anything, verify the project's RERA registration number directly on the Telangana RERA portal — never take a builder's word or a printed brochure as proof.",
            "Cross-check the promised possession date against the RERA filing, not the sales team's verbal assurance. Delays beyond the RERA-committed date entitle you to compensation under Section 18.",
            "Request the encumbrance certificate for the last 13 years and have an independent lawyer verify chain of title, especially for open plots and villa layouts.",
            "Finally, insist on a payment schedule tied to construction milestones (CLP — Construction Linked Plan) rather than a time-based schedule, which shifts delivery risk back onto the builder.",
          ],
        },
        {
          slug: "commercial-real-estate-yields",
          title: "Grade A Office Yields Are Beating Residential — Here's the Data",
          excerpt: "Pre-leased commercial assets in the Financial District are now yielding upwards of 9% annually.",
          image: :office_1, category: "Market Insight", date: "2026-04-08", read_time: "7 min read",
          author_name: "Rahul Sharma", author_role: "Senior Investment Advisor", author_avatar: 11,
          content: [
            "Pre-leased Grade A office assets in the Financial District are now trading at rental yields of 8.5-9.2%, compared to 2.5-3.5% for comparable residential investments in the same micro-market.",
            "The driver is simple: global capability centre expansion has outpaced new Grade A supply for six consecutive quarters, pushing vacancy below 4% across our tracked buildings.",
            "The trade-off is liquidity and ticket size — commercial floor plates typically require ₹2.5 Cr+ entry and a longer resale cycle than residential units.",
            "For investors who can absorb the ticket size, we see this yield gap persisting for at least another 18-24 months before new supply catches up.",
          ],
        },
        {
          slug: "financial-district-office-boom",
          title: "Inside the Financial District's Office Construction Boom",
          excerpt: "Six new Grade A towers are underway. We mapped every one against absorption and rental data.",
          image: :building_modern_1, category: "Market Insight", date: "2026-03-22", read_time: "6 min read",
          author_name: "Sneha Rao", author_role: "Client Relationship Manager", author_avatar: 45,
          content: [
            "Six new Grade A office towers totaling 8.2 million sq.ft are currently under construction across the Financial District, the largest concentrated commercial pipeline in Hyderabad's history.",
            "Pre-leasing activity suggests demand will absorb this supply within 24 months of completion — four of the six towers already have anchor tenants committed for over 40% of leasable area.",
            "For investors, this signals continued upward pressure on both office and adjacent residential pricing through 2028.",
          ],
        },
        {
          slug: "first-time-investor-mistakes",
          title: "Five Mistakes First-Time Real Estate Investors Keep Making",
          excerpt: "From skipping legal due diligence to over-leveraging — patterns we see again and again.",
          image: :living_room_1, category: "Buyer's Guide", date: "2026-02-14", read_time: "5 min read",
          author_name: "Priya Reddy", author_role: "Investment Advisor", author_avatar: 47,
          content: [
            "The most common mistake is buying on emotion during a site visit rather than against a documented investment thesis — layout, budget, and exit horizon should be decided before you ever step into a sample flat.",
            "Second is skipping independent legal due diligence because the builder is 'well known' — reputation is not a substitute for a lawyer's review of title documents.",
            "Third is over-leveraging on EMI without stress-testing for a rate hike — we recommend keeping EMI under 35% of monthly income even at a 2-point higher rate than currently offered.",
            "Fourth is ignoring resale liquidity — some hyper-niche layouts (odd bedroom counts, unusual facing) take significantly longer to exit.",
            "Fifth is not tracking possession-linked payment milestones, which is the single biggest lever you have if a project gets delayed.",
          ],
        },
      ].freeze

      def seed_blogs!
        BLOGS.each do |row|
          App::Models::Blog.find_or_create(slug: row[:slug]) do |b|
            b.title = row[:title]
            b.excerpt = row[:excerpt]
            b.image = IMG[row[:image]]
            b.category = row[:category]
            b.date = row[:date]
            b.read_time = row[:read_time]
            b.author = { name: row[:author_name], role: row[:author_role], avatar: avatar_url(row[:author_avatar]) }
            b.content = Sequel.pg_array(row[:content])
            b.status = "Published"
          end
        end
        puts "Seeded blogs: #{App::Models::Blog.count}"
      end

      # ---------------------------------------------------------------------
      # 24. Testimonials (frontend/lib/data/testimonials.js) — no natural
      #    key (migrations/0028 has no unique column besides id) —
      #    count-guard.
      # ---------------------------------------------------------------------
      TESTIMONIALS = [
        { name: "Kiran Kumar Reddy", role: "Villa Owner, Sobha Royal Crest", rating: 5, quote: "Buying through REROCK was the best investment decision we made. Transparent pricing, zero surprises.", status: "Approved" },
        { name: "Ayesha Khan", role: "Investor, Brigade Horizon", rating: 5, quote: "The advisory team guided us with complete transparency, from site visit to registration.", status: "Approved" },
        { name: "Vikram Malhotra", role: "Portfolio Client", rating: 5, quote: "Portfolio tracking is incredibly useful — I can see appreciation across all four of my properties in one view.", status: "Approved" },
        { name: "Meenal Deshpande", role: "First-time Buyer, Aparna Zenon", rating: 5, quote: "As a first-time buyer, I expected confusion. Instead, every document and deadline was explained upfront.", status: "Approved" },
        { name: "Srinivas Rao", role: "Commercial Investor", rating: 5, quote: "The ROI calculator and rental yield data matched reality almost to the decimal. Genuinely rare in this industry.", status: "Pending" },
      ].freeze

      def seed_testimonials!
        if App::Models::Testimonial.count.positive?
          puts "Testimonials already seeded (#{App::Models::Testimonial.count} rows) — skipping (no natural key, see Phase 3 header note)."
          return
        end

        TESTIMONIALS.each do |row|
          App::Models::Testimonial.create do |t|
            t.name = row[:name]
            t.role = row[:role]
            t.rating = row[:rating]
            t.quote = row[:quote]
            t.status = row[:status]
            t.show_on_homepage = true
          end
        end
        puts "Seeded testimonials: #{App::Models::Testimonial.count}"
      end

      # ---------------------------------------------------------------------
      # 25. FAQs (frontend/lib/data/faqs.js) — no natural key, count-guard.
      # ---------------------------------------------------------------------
      FAQS = [
        { category: "Buying", q: "Is REROCK Realty a builder or an advisory?", a: "REROCK Realty is a registered real estate investment advisory. We don't construct properties — we curate verified inventory from India's most trusted builders and guide you through the entire buying journey." },
        { category: "Buying", q: "What's your fee structure for buyers?", a: "Our advisory services are free for buyers — we're compensated by our builder partners, and pricing shown to you always matches the builder's official price list." },
        { category: "Buying", q: "Can I negotiate the price shown on the platform?", a: "Listed prices reflect the builder's current price list. Our advisors can flag applicable festive or bulk-booking offers, but we don't alter builder pricing directly." },
        { category: "Legal & RERA", q: "How do you verify RERA approval and legal title?", a: "Every listing on our platform is cross-checked against the Telangana RERA portal, and our legal team independently verifies encumbrance certificates before a property is published." },
        { category: "Legal & RERA", q: "What happens if a project's possession is delayed?", a: "RERA entitles you to compensation for delays beyond the committed date. Our advisory team helps clients file and track these claims where applicable." },
        { category: "Financing", q: "Do you help with home loans and EMI planning?", a: "Our advisors work with 12+ leading banks and NBFCs to help you secure the best rate, and our built-in EMI calculator helps you plan affordability before you commit." },
        { category: "Financing", q: "What's the typical down payment expected?", a: "Most lenders finance 75-80% of the property value, meaning a 20-25% down payment. Our affordability calculator can model this against your income." },
        { category: "Portfolio", q: "Can I track my portfolio after purchase?", a: "Yes — every client gets access to a personal dashboard showing live portfolio valuation, growth charts, documents, and price alerts for their properties." },
        { category: "Portfolio", q: "How often is pricing data updated?", a: "Community and location pricing data is refreshed quarterly, with select high-velocity markets like Kokapet updated monthly." },
        { category: "Investing", q: "Do you offer investment advisory for commercial properties?", a: "Yes — our commercial team specializes in pre-leased Grade A offices, retail, and warehousing with verified rental yield data." },
        { category: "Investing", q: "What's the minimum investment ticket size?", a: "Open plots start around ₹18 L, while apartments typically start from ₹65-70 L depending on location. Commercial assets generally require ₹80 L+." },
      ].freeze

      def seed_faqs!
        if App::Models::Faq.count.positive?
          puts "FAQs already seeded (#{App::Models::Faq.count} rows) — skipping (no natural key, see Phase 3 header note)."
          return
        end

        FAQS.each do |row|
          App::Models::Faq.create do |f|
            f.category = row[:category]
            f.q = row[:q]
            f.a = row[:a]
          end
        end
        puts "Seeded FAQs: #{App::Models::Faq.count}"
      end

      # ---------------------------------------------------------------------
      # 26. Job Openings (frontend/lib/data/careers.js#openRoles) — no
      #    natural key, count-guard.
      # ---------------------------------------------------------------------
      JOB_OPENINGS = [
        { title: "Senior Investment Advisor", department: "Sales & Advisory", location: "Hyderabad", type: "Full-time" },
        { title: "Frontend Engineer (Next.js)", department: "Technology", location: "Hyderabad / Remote", type: "Full-time" },
        { title: "Content Marketing Manager", department: "Marketing", location: "Hyderabad", type: "Full-time" },
        { title: "Legal & Compliance Associate", department: "Legal", location: "Hyderabad", type: "Full-time" },
        { title: "Client Relationship Manager", department: "Client Success", location: "Hyderabad", type: "Full-time" },
        { title: "Data Analyst — Pricing Intelligence", department: "Technology", location: "Remote", type: "Contract" },
      ].freeze

      def seed_job_openings!
        if App::Models::JobOpening.count.positive?
          puts "Job openings already seeded (#{App::Models::JobOpening.count} rows) — skipping (no natural key, see Phase 3 header note)."
          return
        end

        JOB_OPENINGS.each do |row|
          App::Models::JobOpening.create do |j|
            j.title = row[:title]
            j.department = row[:department]
            j.location = row[:location]
            j.type = row[:type]
          end
        end
        puts "Seeded job openings: #{App::Models::JobOpening.count}"
      end

      # ---------------------------------------------------------------------
      # 27. Career Benefits (frontend/lib/data/careers.js#benefits) — no
      #    natural key, count-guard.
      # ---------------------------------------------------------------------
      CAREER_BENEFITS = [
        { title: "Performance-linked bonus", description: "Uncapped incentives tied directly to closed deals and client satisfaction." },
        { title: "Health coverage", description: "Comprehensive medical insurance for you and your immediate family." },
        { title: "Learning stipend", description: "Annual budget for courses, certifications, and conferences." },
        { title: "Flexible leave", description: "Unlimited paid time off, used responsibly." },
      ].freeze

      def seed_career_benefits!
        if App::Models::CareerBenefit.count.positive?
          puts "Career benefits already seeded (#{App::Models::CareerBenefit.count} rows) — skipping (no natural key, see Phase 3 header note)."
          return
        end

        CAREER_BENEFITS.each do |row|
          App::Models::CareerBenefit.create do |b|
            b.title = row[:title]
            b.description = row[:description]
          end
        end
        puts "Seeded career benefits: #{App::Models::CareerBenefit.count}"
      end

      # ---------------------------------------------------------------------
      # 28. SEO Pages (frontend/lib/data/seoPages.js) — real unique `route`
      #    (migrations/0032) — find_or_create, same idiom as Blogs.
      # ---------------------------------------------------------------------
      SEO_PAGES = [
        { route: "/", meta_title: "REROCK REALTY — Your Real Estate Investment Partner", meta_description: "Luxury villas, apartments, plots and commercial spaces across Hyderabad's most trusted communities.", score: 92 },
        { route: "/properties", meta_title: "Properties — REROCK REALTY", meta_description: "Browse luxury apartments, villas, plots and commercial spaces across Hyderabad.", score: 88 },
        { route: "/communities", meta_title: "Communities — REROCK REALTY", meta_description: "Explore Hyderabad's most trusted gated communities and townships.", score: 85 },
        { route: "/builders", meta_title: "Builders — REROCK REALTY", meta_description: "Meet the developers behind Hyderabad's most trusted addresses.", score: 80 },
        { route: "/blog", meta_title: "Blog & Insights — REROCK REALTY", meta_description: "Market intelligence, buyer guides, and investment strategy from the REROCK Journal.", score: 90 },
        { route: "/pricing-trends", meta_title: "Pricing Trends — REROCK REALTY", meta_description: "Compare five-year price appreciation across REROCK's featured communities and locations.", score: 76 },
      ].freeze

      def seed_seo_pages!
        SEO_PAGES.each do |row|
          App::Models::SeoPage.find_or_create(route: row[:route]) do |s|
            s.meta_title = row[:meta_title]
            s.meta_description = row[:meta_description]
            s.score = row[:score]
          end
        end
        puts "Seeded SEO pages: #{App::Models::SeoPage.count}"
      end

      # ---------------------------------------------------------------------
      # 29. Hero Stats (frontend/lib/data/homeContent.js#heroStats) — no
      #    natural key, count-guard.
      # ---------------------------------------------------------------------
      HERO_STATS = [
        { label: "Properties Curated", value: 900, suffix: "+" },
        { label: "Avg. Portfolio Growth", value: 22, suffix: "%" },
        { label: "Trusted Builders", value: 6, suffix: "" },
        { label: "Cr+ Transacted", value: 480, suffix: "+" },
      ].freeze

      def seed_hero_stats!
        if App::Models::HeroStat.count.positive?
          puts "Hero stats already seeded (#{App::Models::HeroStat.count} rows) — skipping (no natural key, see Phase 3 header note)."
          return
        end

        HERO_STATS.each do |row|
          App::Models::HeroStat.create do |s|
            s.label = row[:label]
            s.value = row[:value]
            s.suffix = row[:suffix]
          end
        end
        puts "Seeded hero stats: #{App::Models::HeroStat.count}"
      end

      # ---------------------------------------------------------------------
      # 30. Homepage Settings (frontend/lib/data/homeContent.js#heroSocialProof)
      #    — the lazily-created SINGLETON table (migrations/0034,
      #    services/homepage_settings.rb#item). Seeded here as a plain "row
      #    exists? skip : create the one row" check — there is never more
      #    than one row, so no per-field find_or_create makes sense.
      # ---------------------------------------------------------------------
      def seed_homepage_settings!
        if App::Models::HomepageSetting.first
          puts "Homepage settings already seeded (singleton row exists) — skipping."
          return
        end

        App::Models::HomepageSetting.create do |s|
          s.investors_label = "900+ Investors"
          s.rating_label = "4.9 average rating"
        end
        puts "Seeded homepage settings singleton row."
      end

      # ---------------------------------------------------------------------
      # 31. Notifications (frontend/lib/data/notifications.js) — no natural
      #    key, count-guard. The mock's fake relative `time` strings ("2
      #    hours ago") aren't transcribed anywhere (migrations/0037's own
      #    comment: created_at is the real timestamp, and the frontend
      #    computes a relative display from it client-side) — only `read`
      #    is preserved as-is.
      # ---------------------------------------------------------------------
      NOTIFICATIONS = [
        { type: "price", icon: "TrendingUp", title: "Property price increased", message: "Brigade Horizon, Tower A — price per sq.ft rose 4.2% this quarter.", read: false },
        { type: "visit", icon: "CalendarClock", title: "Site visit tomorrow", message: "Your visit to Sobha Royal Crest is confirmed for 11:00 AM with Priya Reddy.", read: false },
        { type: "recommendation", icon: "Sparkles", title: "New recommendation available", message: "Based on your saved searches — a 3 BHK at Lodha Evergreen just listed.", read: false },
        { type: "portfolio", icon: "PieChart", title: "Portfolio updated", message: "Your portfolio value grew by ₹8.4 L this month across 3 assets.", read: true },
        { type: "document", icon: "FileCheck2", title: "Document verified", message: "Sale agreement for Prestige Lakeside Habitat has been verified and stored.", read: true },
      ].freeze

      def seed_notifications!
        if App::Models::Notification.count.positive?
          puts "Notifications already seeded (#{App::Models::Notification.count} rows) — skipping (no natural key, see Phase 3 header note)."
          return
        end

        NOTIFICATIONS.each do |row|
          App::Models::Notification.create do |n|
            n.type = row[:type]
            n.icon = row[:icon]
            n.title = row[:title]
            n.message = row[:message]
            n.read = row[:read]
          end
        end
        puts "Seeded notifications: #{App::Models::Notification.count}"
      end

      # ---------------------------------------------------------------------
      # 32. Media Items (frontend/lib/data/media.js) — no natural key,
      #    count-guard. No admin page renders this resource yet (per
      #    ARCHITECTURE.md), but the table/backend already exists — seeded
      #    anyway for completeness/future use, per the task. `uploaded_at`
      #    is set explicitly onto the real `created_at` column
      #    (migrations/0038 deliberately has no separate uploaded_at column
      #    — see its own comment), preserving each item's real mock upload
      #    date instead of letting every row default to "now".
      # ---------------------------------------------------------------------
      MEDIA_ITEMS = [
        { src: :building_modern_1, name: "Brigade Horizon — Tower A exterior", tags: ["exterior", "brigade"], uploaded_by: "Arjun Varma", uploaded_at: "2026-06-02" },
        { src: :living_room_1, name: "3BHK show flat — living room", tags: ["interior", "show-flat"], uploaded_by: "Arjun Varma", uploaded_at: "2026-06-04" },
        { src: :pool_1, name: "Community pool deck", tags: ["amenity"], uploaded_by: "Sneha Rao", uploaded_at: "2026-05-28" },
        { src: :kitchen_1, name: "Modular kitchen finish sample", tags: ["interior"], uploaded_by: "Arjun Varma", uploaded_at: "2026-06-10" },
        { src: :clubhouse_1, name: "Clubhouse render", tags: ["amenity", "render"], uploaded_by: "Sneha Rao", uploaded_at: "2026-05-30" },
        { src: :skyline_aerial_1, name: "Financial District aerial", tags: ["location", "aerial"], uploaded_by: "Sneha Rao", uploaded_at: "2026-06-15" },
        { src: :blueprint_1, name: "Master plan blueprint", tags: ["document", "floor-plan"], uploaded_by: "Arjun Varma", uploaded_at: "2026-06-01" },
        { src: :gym_1, name: "Fitness centre", tags: ["amenity"], uploaded_by: "Sneha Rao", uploaded_at: "2026-06-08" },
      ].freeze

      def seed_media_items!
        if App::Models::MediaItem.count.positive?
          puts "Media items already seeded (#{App::Models::MediaItem.count} rows) — skipping (no natural key, see Phase 3 header note)."
          return
        end

        MEDIA_ITEMS.each do |row|
          App::Models::MediaItem.create do |m|
            m.src = IMG[row[:src]]
            m.name = row[:name]
            m.tags = Sequel.pg_array(row[:tags])
            m.uploaded_by = row[:uploaded_by]
            m.created_at = row[:uploaded_at]
          end
        end
        puts "Seeded media items: #{App::Models::MediaItem.count}"
      end

      # ---------------------------------------------------------------------
      # Orchestrator — Phase 1 (Property Catalog), then Phase 2 (CRM + Agent
      # Network), then Phase 3 (Finance, Marketing/CMS, Ops/Logs). Agents/
      # RAM/Portfolio Members are seeded first since Leads/Site Visits/
      # Referrals/Deals conceptually reference them (via plain deferred
      # agent_slug/ram_id strings, not real FKs — see each method's own
      # header note); Leads/Site Visits/Deals also need Property Catalog's
      # real Property/Community/Area rows to resolve their real FKs, so
      # Phase 1 must run first. Phase 3's Invoices/Payments/Taxes need real
      # Deals (and, for Refunds, real Clients) to exist first, so Phase 3
      # runs last, after Phase 2 — Marketing/CMS and Notifications/Media
      # Items have no dependencies and could run anywhere, but are kept in
      # Phase 3 for one single "final phase" checkpoint.
      # ---------------------------------------------------------------------
      def run!
        puts "== Seeding sample data: Phase 1 (Property Catalog) =="
        seed_areas!
        seed_builders!
        seed_property_types!
        seed_amenities!
        seed_property_tags!
        seed_communities!
        seed_properties!
        seed_collections!
        puts "== Phase 1 (Property Catalog) complete =="

        puts "== Seeding sample data: Phase 2 (CRM + Agent Network) =="
        seed_agents!
        seed_ram_members!
        seed_portfolio_members!
        seed_leads!
        seed_site_visits!
        seed_referrals!
        seed_clients!
        seed_deals!
        puts "== Phase 2 (CRM + Agent Network) complete =="

        puts "== Seeding sample data: Phase 3 (Finance, Marketing/CMS, Ops/Logs) =="
        seed_expenses!
        seed_invoices!
        seed_payments!
        seed_refunds!
        seed_taxes!
        seed_blogs!
        seed_testimonials!
        seed_faqs!
        seed_job_openings!
        seed_career_benefits!
        seed_seo_pages!
        seed_hero_stats!
        seed_homepage_settings!
        seed_notifications!
        seed_media_items!
        puts "== Phase 3 (Finance, Marketing/CMS, Ops/Logs) complete =="
        puts "== ALL PHASES COMPLETE — sample data seeding finished =="
      end
    end
  end
end
