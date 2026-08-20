# UAT reset: TRUNCATE every real table (all 48, per the current final schema
# traced through migrations 0001-0076 — activity_logs is the only table any
# migration ever creates that no longer exists, dropped by
# migrations/0071_drop_activity_logs.rb) and reseed exactly 5 rows into each.
#
# Reuses App::Seeds::SampleData wherever its existing seed_*! methods/arrays
# already produce correct rows against the CURRENT schema — but several of
# them do NOT, and this file works around each one rather than editing
# sample_data.rb (per the brief). Discovered while building this script,
# all pre-existing and unrelated to this task:
#
#   - seed_properties! sets `p.created_date=`, `p.rera=`, `p.pricing_trend=` —
#     all three columns were DROPPED by migrations/0073_drop_dead_columns_from_properties.rb.
#     Calling that setter on the current schema raises NoMethodError (Sequel
#     only defines column accessors for columns that still exist), so
#     seed_properties! CRASHES outright against today's schema, not just
#     under-seeds. It also never sets `configuration` (required by
#     Property#validate_configuration whenever the target Community has
#     `unit_types` configured, which every seeded Community does) and two of
#     its 8 rows share the exact title "Luxury 3 BHK" (Property#validate
#     rejects duplicate titles) — both would silently drop rows via
#     `raise_on_save_failure = false` even with the crash fixed. See
#     seed_properties! below for the corrected, from-scratch reimplementation
#     (still built from SampleData::PROPERTIES's own row data).
#   - seed_communities! never sets `rera_status`, which
#     Community#validate has required (presence + must be one of
#     Approved/Pending/Not Registered) since migrations/0072. With
#     `raise_on_save_failure = false`, every single Community row silently
#     fails to save on a genuinely empty table — seed_communities! currently
#     produces ZERO rows against a fresh DB. One seeded row's own `status`
#     ("RERA Approved") also isn't a member of Community::CONSTRUCTION_STATUSES
#     — fixed inline below (see COMMUNITY_STATUS_OVERRIDES).
#   - seed_blogs! assigns `b.content = Sequel.pg_array(row[:content])`, but
#     migrations/0066_convert_blogs_content_to_html.rb converted `content`
#     from a text[] column to a plain text (HTML) column. Assigning a Postgres
#     array literal to a scalar text column is a type error at save time.
#     Fixed below by joining the same paragraph strings into HTML, matching
#     migrations/0066's own escaping.
#   - seed_agents! sets phone numbers as "+91 98480 12345", which fails
#     Agent::PHONE_REGEXP (`\A[6-9]\d{9}\z` — exactly 10 digits, no country
#     code/spaces). seed_clients!/seed_leads! have the same problem in
#     reverse: Client#validate/Lead#validate strip non-digits and require
#     exactly 10 digits left over, but "+91 90140 22110" strips down to 12
#     (country code included). All three currently seed ZERO rows against a
#     fresh DB. Fixed below via `corrected_phone`.
#
# None of this is specific to trimming down to 5 rows — every one of these
# would reproduce on a plain `rake db:seed_sample_data` run against a
# genuinely empty (migrated-only) database today. Flagged in detail in this
# task's report; worth a real fix in sample_data.rb separately.

require "date"
require_relative "sample_data"

module App
  module Seeds
    module ResetAndReseed
      module_function

      SD = App::Seeds::SampleData

      # Final-schema table list (48), truncation/seed order doubles as a
      # valid FK-dependency order for the seed phases below (TRUNCATE ...
      # CASCADE makes the order irrelevant for the truncate step itself).
      ALL_TABLES = %w[
        roles users builders property_types areas locations amenities property_tags
        communities properties collections clients agents ram_members portfolio_members
        leads site_visits referral_links referrals deals commissions expenses invoices
        payments refunds taxes blogs testimonials faqs job_openings career_benefits
        seo_pages hero_stats homepage_settings audit_logs notifications media_items
        follow_ups approvals reviews notification_reads recommendations documents
        saved_properties price_histories job_applications newsletter_subscribers
        contact_messages
      ].freeze

      def truncate_all!
        App.db.run("TRUNCATE #{ALL_TABLES.join(', ')} RESTART IDENTITY CASCADE")
        puts "Truncated all #{ALL_TABLES.size} tables (RESTART IDENTITY CASCADE)."
      end

      # Deletes every row of `model` whose `field` is NOT one of `values` —
      # i.e. keeps only the given natural keys. Used to bring an
      # already-fully-seeded (via the reused SampleData method) table down to
      # exactly 5 rows without having to reimplement its per-row creation
      # logic.
      def keep_only!(model, field, values)
        model.exclude(field => values).delete
      end

      # Deletes every row beyond the first `n` by id. Safe for the
      # no-natural-key, count-guarded SampleData tables (Referrals/Deals/
      # Expenses/FAQs/Job Openings/Media Items) since RESTART IDENTITY means
      # id order == the array's own insertion order.
      def keep_first!(model, n = 5)
        extra_ids = model.order(:id).select_map(:id).drop(n)
        model.where(id: extra_ids).delete if extra_ids.any?
      end

      # SampleData's mock phone numbers are "+91 90140 22110" — Agent's
      # PHONE_REGEXP and Client/Lead's own 10-digit checks both reject that
      # shape (see header note). Strips everything but digits and keeps the
      # last 10 (drops the "91" country code), which is exactly what every
      # affected model actually requires.
      def corrected_phone(raw)
        raw.to_s.gsub(/\D/, "")[-10..-1]
      end

      # =======================================================================
      # 1-2. Roles / Users — genuinely new tables (not seeded by
      #    sample_data.rb at all; Rakefile's own db:seed task only creates one
      #    super-admin role + user). Users reference Roles by slug.
      # =======================================================================
      # The real permission gate (routes.rb#require_permission!, only active
      # when ENFORCE_PERMISSIONS=true) does a plain array `.include?("module.
      # action")` check — no wildcard expansion. The flag strings below used
      # to be placeholders ("properties.*", "crm.leads", "finance.*", "cms.*")
      # that don't match that format at all (and "finance"/"cms" aren't even
      # real module keys — see routes.rb's RESOURCE_PERMISSION_MODULES).
      # Flipping ENFORCE_PERMISSIONS=true against the old data would have
      # locked every seeded non-super-admin account out of everything. Fixed
      # here by expanding real flags off the same module->actions taxonomy as
      # the frontend's lib/data/staff.js#permissionModules (kept in sync by
      # hand — this seed file has no access to frontend JS).
      PERMISSION_TAXONOMY = {
        "dashboard" => %w[view],
        "crm" => %w[view create edit delete export import],
        "communities" => %w[view create edit delete publish archive export import],
        "properties" => %w[view create edit delete publish archive export import duplicate],
        "propertyTypes" => %w[view create edit delete],
        "builders" => %w[view create edit delete archive],
        "locations" => %w[view create edit delete],
        "areas" => %w[view create edit delete],
        "pricing" => %w[view edit export import],
        "agentNetwork" => %w[view create edit delete],
        "marketing" => %w[view create edit delete publish approve reject],
        "mediaLibrary" => %w[view upload download delete],
        "reports" => %w[view export],
        "notifications" => %w[view create manage],
        "users" => %w[view create edit delete manage],
        "roles" => %w[view create edit delete manage],
        "permissions" => %w[view manage],
        "auditLogs" => %w[view export restore],
        "settings" => %w[view manage],
      }.freeze

      # `only:` narrows a module to a subset of its own actions (e.g. a
      # view-only grant); omitted, every action the taxonomy lists for that
      # module is included.
      def self.module_flags(*modules, only: nil)
        modules.flat_map { |m| (only || PERMISSION_TAXONOMY.fetch(m)).map { |a| "#{m}.#{a}" } }
      end

      ROLES = [
        { slug: "role-super-admin", name: "Super Admin", level: 0, is_super_admin: true, status: "Active",
          description: "Full, unrestricted access to every module.", permissions: ["*"] },
        # "Every module except Roles and Permissions administration" — same
        # scope as the frontend mock's own Admin role (lib/data/staff.js's
        # `nonAdminFlags`: every real flag except roles.* and
        # permissions.manage). Roles/Permissions administration stays
        # Super-Admin-only; everything else, including full Users/Audit Logs
        # management, is granted.
        { slug: "role-admin", name: "Admin", level: 1, is_super_admin: false, status: "Active",
          description: "Broad operational access across CRM, listings, and finance.",
          permissions: module_flags(*(PERMISSION_TAXONOMY.keys - %w[roles permissions])) },
        { slug: "role-sales-manager", name: "Sales Manager", level: 5, is_super_admin: false, status: "Active",
          description: "Manages agents, leads, deals, and site visits.",
          permissions: module_flags("dashboard") +
            module_flags("crm", only: %w[view create edit export]) +
            module_flags("agentNetwork", only: %w[view create edit]) +
            module_flags("reports", only: %w[view]) },
        # Invoices/Payments/Refunds/Taxes have no permission module of their
        # own yet (routes.rb deliberately leaves them unenforced — see its
        # RESOURCE_PERMISSION_MODULES comment), so this role's real enforced
        # surface is narrower than its description implies until that gap is
        # closed. Flagged here rather than silently worked around.
        { slug: "role-finance-manager", name: "Finance Manager", level: 5, is_super_admin: false, status: "Active",
          description: "Manages invoices, payments, refunds, and taxes.",
          permissions: module_flags("dashboard") + module_flags("pricing") + module_flags("reports") +
            module_flags("crm", only: %w[view export]) },
        { slug: "role-content-editor", name: "Content Editor", level: 8, is_super_admin: false, status: "Active",
          description: "Manages blogs, testimonials, FAQs, and SEO pages.",
          permissions: module_flags("dashboard") + module_flags("marketing") +
            module_flags("mediaLibrary", only: %w[view upload download]) },
      ].freeze

      def seed_roles!
        ROLES.each do |row|
          App::Models::Role.find_or_create(slug: row[:slug]) do |r|
            r.name = row[:name]
            r.level = row[:level]
            r.is_super_admin = row[:is_super_admin]
            r.status = row[:status]
            r.description = row[:description]
            r.permissions = Sequel.pg_array(row[:permissions])
          end
        end
        puts "Seeded roles: #{App::Models::Role.count}"
      end

      # `designation` dropped from every row below: models/user.rb now
      # restricts it to User::DESIGNATIONS (Agent/RAM/Client) and none of
      # these five admin-staff seed accounts are actually any of those —
      # forcing one on to satisfy the new constraint would just be wrong
      # data. `department` (a separate, still-free-text column) already
      # carries the meaningful "what team are they on" info for these rows.
      USERS = [
        { full_name: "Admin User", email: "admin.user@rerockrealty.com", role_slug: "role-super-admin", department: "Management" },
        { full_name: "Ops Admin", email: "ops.admin@rerockrealty.com", role_slug: "role-admin", department: "Operations" },
        { full_name: "Sales Manager", email: "sales.manager@rerockrealty.com", role_slug: "role-sales-manager", department: "Sales" },
        { full_name: "Finance Manager", email: "finance.manager@rerockrealty.com", role_slug: "role-finance-manager", department: "Finance" },
        { full_name: "Content Editor", email: "content.editor@rerockrealty.com", role_slug: "role-content-editor", department: "Marketing" },
      ].freeze

      def seed_users!
        USERS.each do |row|
          role = App::Models::Role.first(slug: row[:role_slug])
          user = App::Models::User.first(email: row[:email])
          next if user

          user = App::Models::User.new(
            full_name: row[:full_name],
            email: row[:email],
            role_id: role&.id,
            designation: row[:designation],
            department: row[:department],
            active: true
          )
          user.password = "ChangeMe123!"
          user.save
        end
        puts "Seeded users: #{App::Models::User.count}"
      end

      # =======================================================================
      # 3. Builders / 5-6. Areas+Locations / 7-8. Amenities+Property Tags —
      #    none of these have any validation/schema mismatch against the
      #    current models (verified against every column-dropping migration),
      #    so the original SampleData seed_*! methods run correctly; only the
      #    row COUNT needs trimming. Builders/Areas/Locations are trimmed to a
      #    hand-picked, mutually-consistent set (not a blind "first 5") since
      #    Communities/Properties below need one specific builder+area+
      #    location per community, and a plain array-order prefix does not
      #    line up (e.g. the 5th/6th Builders in array order are "aparna"/
      #    "my-home", but My Home Avatar — one of the 5 Communities kept — is
      #    the one that needs "my-home", not "aparna").
      # =======================================================================
      KEEP_BUILDER_SLUGS = %w[brigade prestige sobha lodha my-home].freeze
      KEEP_AREA_SLUGS = %w[kokapet tellapur narsingi gachibowli kondapur].freeze
      KEEP_LOCATION_SLUGS = %w[kokapet-phase-1 tellapur-main-road narsingi-villas gachibowli-central kondapur-main].freeze

      # Reimplemented (not a thin SD.seed_builders! wrapper + trim, unlike
      # Areas/Locations/Amenities/Property Tags/Collections below): SD::BUILDERS'
      # mock phone numbers are "+91 80 4132 6999" — Builder#validate's
      # `phone.gsub(/\D/, '').length != 10` check counts the country code as
      # part of the digit string (12 digits, not 10) and rejects every single
      # row, so SD.seed_builders! silently seeds ZERO builders against the
      # current schema (same class of bug as the phone issues in the header
      # note, just not one that was caught before this ran for real). Fixed
      # here via `corrected_phone`, same as Agents/Clients/Leads.
      def seed_builders!
        SD::BUILDERS.each do |row|
          next unless KEEP_BUILDER_SLUGS.include?(row[:slug])

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
            b.phone = corrected_phone(row[:phone])
            b.description = row[:description]
            b.headline = row[:headline]
            b.awards = Sequel.pg_array(row[:awards])
            b.documents = row[:documents]
          end
        end
        puts "Seeded builders: #{App::Models::Builder.count}"
      end

      def seed_property_types!
        SD.seed_property_types!
      end

      def seed_areas_and_locations!
        SD.seed_areas!
        SD.seed_locations!
        # Locations must be trimmed before Areas — a kept Location still
        # holding a foreign key into a to-be-dropped Area would otherwise
        # violate the FK constraint on delete.
        keep_only!(App::Models::Location, :slug, KEEP_LOCATION_SLUGS)
        keep_only!(App::Models::Area, :slug, KEEP_AREA_SLUGS)
        puts "Trimmed areas: #{App::Models::Area.count}, locations: #{App::Models::Location.count}"
      end

      def seed_amenities!
        SD.seed_amenities!
        keep_only!(App::Models::Amenity, :slug, SD::AMENITIES.first(5).map { |a| a[:slug] })
        puts "Trimmed amenities: #{App::Models::Amenity.count}"
      end

      def seed_property_tags!
        SD.seed_property_tags!
        keep_only!(App::Models::PropertyTag, :slug, SD::PROPERTY_TAGS.first(5).map { |a| a[:slug] })
        puts "Trimmed property tags: #{App::Models::PropertyTag.count}"
      end

      # =======================================================================
      # 9. Communities — reimplemented from scratch (not a thin wrapper around
      #    SD.seed_communities!) to fix the missing `rera_status` (required by
      #    Community#validate — see header note) and My Home Avatar's invalid
      #    `status` value. Still built directly from SampleData::COMMUNITIES's
      #    own row data/IMG/trend helpers, just for 5 hand-picked slugs.
      # =======================================================================
      COMMUNITY_SLUGS_KEEP = %w[brigade-horizon prestige-lakeside sobha-royal-crest lodha-evergreen my-home-avatar].freeze
      # Two of the 5 kept Properties (below) are commercial units attached to
      # a residential Community in the original mock data (a pre-existing
      # mismatch) — Property#validate_configuration requires `configuration`
      # to be one of the Community's own `unit_types`, so a matching entry is
      # appended here for exactly those two Communities.
      COMMUNITY_UNIT_TYPE_ADDITIONS = { "my-home-avatar" => "Retail", "lodha-evergreen" => "Warehouse" }.freeze
      # My Home Avatar's mock `status` is "RERA Approved", not a member of
      # Community::CONSTRUCTION_STATUSES (['Under Construction', 'Ready To
      # Move', 'Completed']) — Community#validate rejects it outright.
      COMMUNITY_STATUS_OVERRIDES = { "my-home-avatar" => "Ready To Move" }.freeze

      def seed_communities!
        SD::COMMUNITIES.each do |row|
          next unless COMMUNITY_SLUGS_KEEP.include?(row[:slug])

          builder = App::Models::Builder.first(slug: row[:builder_slug])
          area = App::Models::Area.first(slug: row[:area_slug])
          location = App::Models::Location.first(slug: row[:location_slug])
          if builder.nil? || area.nil? || location.nil?
            warn "[seed_communities!] skipping '#{row[:slug]}': missing builder/area/location"
            next
          end

          amenity_ids = App::Models::Amenity.where(slug: row[:amenity_slugs]).select_map(:id)
          unit_types = row[:unit_types] + [COMMUNITY_UNIT_TYPE_ADDITIONS[row[:slug]]].compact

          App::Models::Community.find_or_create(slug: row[:slug]) do |c|
            c.name = row[:name]
            c.builder_id = builder.id
            c.area_id = area.id
            c.location_id = location.id
            c.tagline = row[:tagline]
            c.status = COMMUNITY_STATUS_OVERRIDES[row[:slug]] || row[:status]
            c.featured = row[:featured]
            c.trending = row[:trending]
            c.homepage_visibility = row[:homepage_visibility]
            c.rera = row[:rera]
            c.rera_status = "Approved"
            c.price_min = row[:price_min]
            c.price_max = row[:price_max]
            c.unit_types = Sequel.pg_array(unit_types)
            c.total_units = row[:total_units]
            c.available_units = row[:available_units]
            c.possession = row[:possession]
            c.investment_score = row[:investment_score]
            c.growth_pct = row[:growth_pct]
            c.last_price_update = row[:last_price_update]
            c.hero_image = SD::IMG[row[:hero_image]]
            c.gallery = Sequel.pg_array(row[:gallery].map { |k| SD::IMG[k] })
            c.overview = row[:overview]
            c.master_plan = row[:master_plan]
            c.amenity_ids = Sequel.pg_array(amenity_ids, :integer)
            c.pricing_trend = SD.trend(row[:pricing_trend_base])
            c.nearby = row[:nearby]
          end
        end
        puts "Seeded communities: #{App::Models::Community.count}"
      end

      # =======================================================================
      # 10. Properties — reimplemented from scratch (see header note):
      #    SD.seed_properties! sets 3 dropped columns (crashes outright on the
      #    current schema), never sets the now-required `configuration`, and
      #    2 of its 8 rows share an identical title. All fixed below for the
      #    5 kept slugs.
      # =======================================================================
      PROPERTY_SLUGS_KEEP = %w[
        brigade-horizon-3bhk-tower-a sobha-royal-crest-5bhk-villa kondapur-high-street-retail
        gachibowli-logistics-warehouse prestige-lakeside-3bhk
      ].freeze
      PROPERTY_CONFIGURATION = {
        "brigade-horizon-3bhk-tower-a" => "3 BHK",
        "sobha-royal-crest-5bhk-villa" => "5 BHK Villa",
        "kondapur-high-street-retail" => "Retail",
        "gachibowli-logistics-warehouse" => "Warehouse",
        "prestige-lakeside-3bhk" => "3 BHK",
      }.freeze
      # Original mock title collided with brigade-horizon-3bhk-tower-a's own
      # "Luxury 3 BHK" — Property#validate rejects a duplicate title.
      PROPERTY_TITLE_OVERRIDES = { "prestige-lakeside-3bhk" => "Luxury 3 BHK — Lakeside" }.freeze

      def seed_properties!
        SD::PROPERTIES.each do |row|
          next unless PROPERTY_SLUGS_KEEP.include?(row[:slug])

          community = App::Models::Community.first(slug: row[:community_slug])
          builder = App::Models::Builder.first(slug: row[:builder_slug])
          area = App::Models::Area.first(slug: row[:area_slug])
          location = App::Models::Location.first(slug: row[:location_slug])
          property_type = App::Models::PropertyType.first(name: row[:type_name])
          if community.nil? || builder.nil? || area.nil? || location.nil? || property_type.nil?
            warn "[seed_properties!] skipping '#{row[:slug]}': missing FK"
            next
          end

          tag_ids = App::Models::PropertyTag.where(slug: row[:tag_slugs]).select_map(:id)

          App::Models::Property.find_or_create(slug: row[:slug]) do |p|
            p.title = PROPERTY_TITLE_OVERRIDES[row[:slug]] || row[:title]
            p.community_id = community.id
            p.builder_id = builder.id
            p.area_id = area.id
            p.location_id = location.id
            p.property_type_id = property_type.id
            p.status = row[:status]
            p.price = row[:price]
            p.price_per_sqft = row[:price_per_sqft]
            p.built_up_area = row[:built_up_area]
            p.land_area = row[:land_area]
            p.bedrooms = row[:bedrooms]
            p.bathrooms = row[:bathrooms]
            p.balconies = row[:balconies]
            p.facing = row[:facing]
            p.floor = row[:floor]
            p.images = Sequel.pg_array(row[:images].map { |k| SD::IMG[k] })
            p.highlights = Sequel.pg_array(row[:highlights])
            p.description = row[:description]
            p.floor_plans = row[:floor_plans].map { |fp| { label: fp[:label], image: SD::IMG[fp[:image]] } }
            p.agent_slug = row[:agent_slug]
            p.featured = row[:featured]
            p.tag_ids = Sequel.pg_array(tag_ids, :integer)
            p.configuration = PROPERTY_CONFIGURATION[row[:slug]]
            p.publish_status = "Published"
          end
        end
        puts "Seeded properties: #{App::Models::Property.count}"
      end

      # =======================================================================
      # 11. Collections — no validation issues; just needs Properties seeded
      #    first (done above).
      # =======================================================================
      def seed_collections!
        SD.seed_collections!
        keep_only!(App::Models::Collection, :slug, SD::COLLECTIONS.first(5).map { |c| c[:slug] })
        puts "Trimmed collections: #{App::Models::Collection.count}"
      end

      # =======================================================================
      # 12. Clients — reimplemented (not a thin wrapper): phone numbers need
      #    `corrected_phone` (see header note). Otherwise identical to
      #    SD.seed_clients!, just scoped to the first 5 rows.
      # =======================================================================
      CLIENT_ROWS_KEEP = SD::CLIENTS.first(5).freeze
      # SD::CLIENTS' assigned_ram_id ("ram1"/"ram2"/"ram3") is SD::RAM_MEMBERS'
      # internal mock_id, NOT a real RamMember#slug — RamMember#slug is always
      # `slugify(name)` (e.g. "neha-kapoor"), set by seed_ram_members! itself.
      # Client#validate checks assigned_ram_id against a real RamMember.slug
      # match unconditionally on every new record, so passing the raw mock_id
      # through as-is (what SD.seed_clients! itself does) makes that check
      # fail every time and — since Sequel::Model.raise_on_save_failure is
      # false app-wide (app.rb) — silently seeds ZERO clients. Same class of
      # pre-existing bug as the phone-number issue in the header note; fixed
      # here by mapping mock_id -> real slug before assigning.
      RAM_SLUG_BY_MOCK_ID = SD::RAM_MEMBERS.each_with_object({}) { |r, h| h[r[:mock_id]] = SD.slugify(r[:name]) }.freeze

      def seed_clients!
        CLIENT_ROWS_KEEP.each do |row|
          App::Models::Client.find_or_create(email: row[:email]) do |c|
            c.name = row[:name]
            c.phone = corrected_phone(row[:phone])
            c.avatar = SD.avatar_url(row[:avatar])
            c.joined = row[:joined]
            c.status = row[:status]
            c.assigned_agent_slug = row[:assigned_agent_slug]
            c.assigned_ram_id = RAM_SLUG_BY_MOCK_ID[row[:assigned_ram_id]]
            c.type = row[:type]
            c.city = row[:city]
            c.referral_source = row[:referral_source]
            c.invested_properties = SD.resolve_invested_properties(row[:invested_properties])
            c.notes = row[:notes]
            c.communication_log = row[:communication_log]
            c.timeline = row[:timeline]
          end
        end

        email_by_mock_id = CLIENT_ROWS_KEEP.each_with_object({}) { |r, h| h[r[:mock_id]] = r[:email] }
        CLIENT_ROWS_KEEP.each do |row|
          next if row[:referred_by_mock_id].nil?

          referrer_email = email_by_mock_id[row[:referred_by_mock_id]]
          next if referrer_email.nil?

          client = App::Models::Client.first(email: row[:email])
          referrer = App::Models::Client.first(email: referrer_email)
          client.update(referred_by_id: referrer.id) if client && referrer
        end

        puts "Seeded clients: #{App::Models::Client.count}"
      end

      # =======================================================================
      # 13. Agents — reimplemented: SD::AGENTS only has 4 rows (a 5th is
      #    added below) and its phone numbers need `corrected_phone` to pass
      #    Agent::PHONE_REGEXP (see header note).
      # =======================================================================
      AGENT_ROWS_KEEP = (SD::AGENTS + [{
        slug: "kavya-iyer", name: "Kavya Iyer", role: "Investment Advisor",
        email: "kavya.iyer@rerockrealty.com", phone: "9876543210", whatsapp: "919876543210",
        avatar: 24, specialization: "Apartments & Commercial", deals_closed: 58, rating: 4.6,
        experience_years: 4, strong_area_slugs: ["kondapur", "gachibowli"],
        address: "REROCK Realty, Kondapur, Hyderabad", status: "Active",
        territory: "Kondapur & Gachibowli", bookings: 6, revenue: 9_600_000,
        conversion_rate: 5.1, commission_rate: 1.25, commission_earned: 120_000, pending_commission: 18_000,
        leads_assigned: 15, joined_date: "2022-08-01",
        commission_monthly: [{ month: "Jul", earned: 42_000 }],
        tasks: [], attendance: [], properties_sold: [], properties_assigned: [], documents: [], activity_log: [],
      }]).freeze

      def seed_agents!
        AGENT_ROWS_KEEP.each do |row|
          strong_area_ids = App::Models::Area.where(slug: row[:strong_area_slugs]).select_map(:id)

          App::Models::Agent.find_or_create(slug: row[:slug]) do |a|
            a.name = row[:name]
            a.role = row[:role]
            a.email = row[:email]
            a.phone = corrected_phone(row[:phone])
            a.whatsapp = row[:whatsapp]
            a.avatar = SD.avatar_url(row[:avatar])
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

      # =======================================================================
      # 14-15. RAM Members / Portfolio Members — SampleData's own rows are
      #    valid as-is (only 3 each); 2 more of each are appended directly.
      # =======================================================================
      RAM_MEMBERS_EXTRA = [
        { name: "Ritika Chawla", email: "ritika.c@rerockrealty.com", avatar: 22, designation: "RAM", region: "South Hyderabad",
          phone: "9848011104", default_commission_rate: 1.25, profession: "Real Estate Advisor", date_of_birth: "1990-06-18",
          deals_this_quarter: 10, status: "Active", satisfaction: 4.5,
          renewal_rate: 78, avg_response_time_hours: 4, experience_years: 4, revenue_managed: 4_800_000,
          conversion_rate_pct: 65, referral_generated: 520_000 },
        { name: "Sameer Joshi", email: "sameer.j@rerockrealty.com", avatar: 36, designation: "RAM", region: "East Hyderabad",
          phone: "9848011105", default_commission_rate: 1.0, profession: "Real Estate Advisor", date_of_birth: "1993-11-05",
          deals_this_quarter: 8, status: "Active", satisfaction: 4.3,
          renewal_rate: 74, avg_response_time_hours: 6, experience_years: 3, revenue_managed: 3_600_000,
          conversion_rate_pct: 60, referral_generated: 410_000 },
      ].freeze

      def seed_ram_members!
        SD.seed_ram_members!
        RAM_MEMBERS_EXTRA.each do |row|
          App::Models::RamMember.find_or_create(email: row[:email]) do |r|
            r.slug = SD.slugify(row[:name])
            r.name = row[:name]
            r.avatar = SD.avatar_url(row[:avatar])
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
            r.recommendations = []
            r.reports = []
            r.performance = []
            r.activities = []
            r.documents = []
          end
        end
        puts "Seeded RAM members: #{App::Models::RamMember.count}"
      end

      PORTFOLIO_MEMBERS_EXTRA = [
        { name: "Nikhil Verma", email: "nikhil.verma@rerockrealty.com", avatar: 12, clients_managed: 28, aum: 165_000_000, rating: 4.5, ram_email: "ritika.c@rerockrealty.com" },
        { name: "Priyanka Rao", email: "priyanka.rao@rerockrealty.com", avatar: 33, clients_managed: 33, aum: 198_000_000, rating: 4.7, ram_email: "sameer.j@rerockrealty.com" },
      ].freeze

      def seed_portfolio_members!
        SD.seed_portfolio_members!
        PORTFOLIO_MEMBERS_EXTRA.each do |row|
          ram = App::Models::RamMember.first(email: row[:ram_email])
          App::Models::PortfolioMember.find_or_create(email: row[:email]) do |m|
            m.name = row[:name]
            m.avatar = SD.avatar_url(row[:avatar])
            m.clients_managed = row[:clients_managed]
            m.aum = row[:aum]
            m.rating = row[:rating]
            m.ram_member_id = ram&.id
          end
        end
        puts "Seeded portfolio members: #{App::Models::PortfolioMember.count}"
      end

      # =======================================================================
      # 16. Leads — reimplemented: phone needs `corrected_phone` (see header
      #    note); otherwise identical to SD.seed_leads!, scoped to the first 5.
      # =======================================================================
      LEAD_ROWS_KEEP = SD::LEADS.first(5).freeze

      def seed_leads!
        return if App::Models::Lead.count.positive?

        LEAD_ROWS_KEEP.each do |row|
          property = App::Models::Property.first(slug: row[:property_slug])
          community = App::Models::Community.first(slug: row[:community_slug])
          area = App::Models::Area.first(slug: row[:area_slug])

          App::Models::Lead.create do |l|
            l.client_name = row[:client_name]
            l.client_phone = corrected_phone(row[:client_phone])
            l.client_email = row[:client_email]
            l.avatar = SD.avatar_url(row[:avatar])
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
            # Same "ram1"/"ram2"/"ram3" mock_id-vs-real-slug mismatch as
            # CLIENT_ROWS_KEEP's own assigned_ram_id above — SD::LEADS'
            # ram_id is the mock_id, not a real RamMember#slug, so it needs
            # the same RAM_SLUG_BY_MOCK_ID translation.
            l.ram_id = RAM_SLUG_BY_MOCK_ID[row[:ram_id]]
            l.timeline = row[:timeline]
          end
        end
        puts "Seeded leads: #{App::Models::Lead.count}"
      end

      # =======================================================================
      # 17. Site Visits — reimplemented only because the lead lookup has to
      #    key off `corrected_phone` (the original method's own SD::LEADS
      #    phone-based lookup would never match our now-corrected Lead rows).
      # =======================================================================
      SITE_VISIT_ROWS_KEEP = SD::SITE_VISITS.first(5).freeze

      def seed_site_visits!
        return if App::Models::SiteVisit.count.positive?

        lead_phone_by_mock_id = LEAD_ROWS_KEEP.each_with_object({}) { |l, h| h[l[:mock_id]] = corrected_phone(l[:client_phone]) }

        SITE_VISIT_ROWS_KEEP.each do |row|
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

      # =======================================================================
      # 18. Referral Links — new table. `ram_id` is a plain RamMember#slug
      #    string (no DB-level FK, matching migrations/0060's own comment).
      # =======================================================================
      def seed_referral_links!
        ram_members = App::Models::RamMember.order(:id).all
        properties = App::Models::Property.order(:id).all
        rows = [
          { ram: ram_members[0], property: nil, code: "RAM-GEN-0001", clicks_count: 42, active: true },
          { ram: ram_members[1], property: properties[0], code: "RAM-PROP-0002", clicks_count: 18, active: true },
          { ram: ram_members[2], property: properties[1], code: "RAM-PROP-0003", clicks_count: 7, active: true },
          { ram: ram_members[3], property: nil, code: "RAM-GEN-0004", clicks_count: 3, active: false },
          { ram: ram_members[4], property: properties[2], code: "RAM-PROP-0005", clicks_count: 25, active: true },
        ]
        rows.each do |row|
          App::Models::ReferralLink.find_or_create(code: row[:code]) do |l|
            l.ram_id = row[:ram]&.slug
            l.property_id = row[:property]&.id
            l.clicks_count = row[:clicks_count]
            l.active = row[:active]
            l.last_clicked_at = Time.now - 86_400
          end
        end
        puts "Seeded referral links: #{App::Models::ReferralLink.count}"
      end

      # =======================================================================
      # 19-20. Referrals / Deals — no validation/schema issues at all; just
      #    trimmed down from SampleData's own count-guarded full run.
      # =======================================================================
      def seed_referrals!
        SD.seed_referrals!
        keep_first!(App::Models::Referral, 5)
        # SD.seed_referrals! copies SD::REFERRALS' `ram_id` through unchanged
        # (same "mock_id, not a real RamMember#slug" mismatch as
        # CLIENT_ROWS_KEEP's own assigned_ram_id / seed_leads!'s own ram_id
        # above) — unlike Client#validate, Referral has no server-side check
        # that would catch this, so it silently seeds successfully with the
        # wrong string. That wrong value then flows straight into
        # Commission#ram_id (seed_commissions! below just copies
        # `ref.ram_id` verbatim), which is what left every seeded
        # Commission#ram_member_id nil (RamMember.where(slug: "ram2") never
        # matches) and made the Admin Commissions page fall back to
        # showing the raw "ram1"/"ram2" string instead of the RAM's real
        # name. Fixed the same way, after the fact since SD.seed_referrals!
        # doesn't take a translation hook.
        App::Models::Referral.all.each do |ref|
          real_slug = RAM_SLUG_BY_MOCK_ID[ref.ram_id]
          ref.update(ram_id: real_slug) if real_slug && real_slug != ref.ram_id
        end
        puts "Trimmed referrals: #{App::Models::Referral.count}"
      end

      def seed_deals!
        SD.seed_deals!
        keep_first!(App::Models::Deal, 5)
        puts "Trimmed deals: #{App::Models::Deal.count}"
      end

      # =======================================================================
      # 21. Commissions — new table. One per kept Referral (Commission has a
      #    real not-null `referral_id` FK).
      # =======================================================================
      def seed_commissions!
        referrals = App::Models::Referral.order(:id).all
        deals = App::Models::Deal.order(:id).all
        statuses = %w[PENDING ELIGIBLE UNDER_REVIEW APPROVED PAID]

        referrals.each_with_index do |ref, i|
          App::Models::Commission.find_or_create(referral_id: ref.id) do |c|
            c.deal_id = deals[i]&.id
            c.ram_id = ref.ram_id
            c.sale_amount = ref.reward.to_i * 20 + 1_000_000
            c.commission_rate = 1.0
            c.commission_amount = (c.sale_amount * c.commission_rate / 100.0).round
            c.status = statuses[i % statuses.length]
            c.notes = "Auto-generated for #{ref.referred}"
          end
        end
        puts "Seeded commissions: #{App::Models::Commission.count}"
      end

      # =======================================================================
      # 22. Expenses — no validation issues; trimmed from the full run.
      # =======================================================================
      def seed_expenses!
        SD.seed_expenses!
        keep_first!(App::Models::Expense, 5)
        puts "Trimmed expenses: #{App::Models::Expense.count}"
      end

      # =======================================================================
      # 23-25. Invoices / Payments / Taxes — SD's own generators derive N
      #    invoices, 2N payments, and 2N taxes from however many Deals are
      #    "Closed" (N), which can never simultaneously equal 5 for all three
      #    tables. Reimplemented as one fixed row per (5) Deal instead, reusing
      #    SD's own status/mode/rate constants and add_days/month_label
      #    helpers for style consistency.
      # =======================================================================
      def seed_invoices!
        App::Models::Deal.order(:id).all.each_with_index do |deal, i|
          App::Models::Invoice.create do |inv|
            inv.deal_id = deal.id
            inv.client_id = deal.client_id
            inv.client_name = deal.client_name
            inv.property_name = deal.property_name
            inv.agent_slug = deal.agent_slug
            inv.amount = deal.value
            inv.status = SD::INVOICE_STATUSES[i % SD::INVOICE_STATUSES.length]
            inv.issued_date = deal.closing_date
            inv.due_date = SD.add_days(deal.closing_date, 30)
          end
        end
        puts "Seeded invoices: #{App::Models::Invoice.count}"
      end

      def seed_payments!
        App::Models::Deal.order(:id).all.each_with_index do |deal, i|
          closed = deal.stage == "Closed"
          App::Models::Payment.create do |pmt|
            pmt.deal_id = deal.id
            pmt.client_id = deal.client_id
            pmt.client_name = deal.client_name
            pmt.milestone = closed ? "Final Payment" : "Booking Advance"
            pmt.amount = closed ? deal.value : (deal.value * 0.2).round
            pmt.mode = SD::PAYMENT_MODES[i % SD::PAYMENT_MODES.length]
            pmt.paid_date = deal.closing_date
          end
        end
        puts "Seeded payments: #{App::Models::Payment.count}"
      end

      def seed_taxes!
        App::Models::Deal.order(:id).all.each_with_index do |deal, i|
          type = SD::TAX_TYPES[i % SD::TAX_TYPES.length]
          App::Models::Tax.create do |t|
            t.deal_id = deal.id
            t.type = type
            t.amount = (deal.value.to_i * SD::TAX_RATE_PCT[type] / 100.0).round
            t.period = SD.month_label(deal.closing_date)
            t.status = SD::TAX_STATUSES[i % SD::TAX_STATUSES.length]
          end
        end
        puts "Seeded taxes: #{App::Models::Tax.count}"
      end

      # =======================================================================
      # 26. Refunds — no validation issues; SampleData only has 4 rows, one
      #    more is appended.
      # =======================================================================
      def seed_refunds!
        SD.seed_refunds!
        App::Models::Refund.find_or_create(client_name: "Srinivas Rao", property_name: "Financial District — Grade A Office, Unit 2") do |r|
          client = App::Models::Client.first(name: "Srinivas Rao")
          r.client_id = client&.id
          r.amount = 275_000
          r.reason = "Partial refund on maintenance deposit overpayment"
          r.status = "Requested"
          r.requested_date = "2026-07-05"
        end
        puts "Seeded refunds: #{App::Models::Refund.count}"
      end

      # =======================================================================
      # 27. Blogs — reimplemented: `content` needs to be an HTML string, not
      #    a pg_array (see header note); otherwise identical to SD.seed_blogs!,
      #    scoped to the first 5 by slug.
      # =======================================================================
      def seed_blogs!
        SD::BLOGS.first(5).each do |row|
          App::Models::Blog.find_or_create(slug: row[:slug]) do |b|
            b.title = row[:title]
            b.excerpt = row[:excerpt]
            b.image = SD::IMG[row[:image]]
            b.category = row[:category]
            b.date = row[:date]
            b.read_time = row[:read_time]
            b.author = { name: row[:author_name], role: row[:author_role], avatar: SD.avatar_url(row[:author_avatar]) }
            b.content = row[:content].map { |p| "<p>#{p.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')}</p>" }.join
            b.status = "Published"
          end
        end
        puts "Seeded blogs: #{App::Models::Blog.count}"
      end

      # =======================================================================
      # 28-33. Testimonials / FAQs / Job Openings / Career Benefits / SEO
      #    Pages / Hero Stats — no validation/schema issues; each either
      #    already has exactly 5 rows, needs trimming, or needs 1 more added.
      # =======================================================================
      def seed_testimonials!
        SD.seed_testimonials!
      end

      def seed_faqs!
        SD.seed_faqs!
        keep_first!(App::Models::Faq, 5)
        puts "Trimmed FAQs: #{App::Models::Faq.count}"
      end

      def seed_job_openings!
        SD.seed_job_openings!
        keep_first!(App::Models::JobOpening, 5)
        puts "Trimmed job openings: #{App::Models::JobOpening.count}"
      end

      def seed_career_benefits!
        SD.seed_career_benefits!
        App::Models::CareerBenefit.find_or_create(title: "Wellness allowance") do |b|
          b.description = "Monthly reimbursement for gym memberships, therapy, or wellness apps."
        end
        puts "Seeded career benefits: #{App::Models::CareerBenefit.count}"
      end

      def seed_seo_pages!
        SD.seed_seo_pages!
        keep_only!(App::Models::SeoPage, :route, SD::SEO_PAGES.first(5).map { |s| s[:route] })
        puts "Trimmed SEO pages: #{App::Models::SeoPage.count}"
      end

      def seed_hero_stats!
        SD.seed_hero_stats!
        App::Models::HeroStat.find_or_create(label: "Years of Operation") do |s|
          s.value = 15
          s.suffix = "+"
        end
        puts "Seeded hero stats: #{App::Models::HeroStat.count}"
      end

      # =======================================================================
      # 34. Homepage Settings — genuinely a lazily-created SINGLETON in the
      #    running app (services/homepage_settings.rb only ever reads/writes
      #    ONE row; SD.seed_homepage_settings! itself refuses to create a
      #    second). Inserted as 5 plain rows here only to satisfy this
      #    script's literal "exactly 5 rows in every table" brief — rows 2-5
      #    are inert filler the app will never read. Flagged clearly in this
      #    task's report; double-check this is actually what you want before
      #    running against a real environment.
      # =======================================================================
      def seed_homepage_settings!
        5.times do |i|
          App::Models::HomepageSetting.create(
            investors_label: i.zero? ? "900+ Investors" : "Variant #{i} - 900+ Investors",
            rating_label: i.zero? ? "4.9 average rating" : "Variant #{i} - 4.9 average rating"
          )
        end
        puts "Seeded homepage settings: #{App::Models::HomepageSetting.count} (singleton table — see comment above)"
      end

      # =======================================================================
      # 35. Audit Logs — new table. System-generated in the real app
      #    (services/base.rb's save hook); plain rows here for seed purposes.
      # =======================================================================
      def seed_audit_logs!
        rows = [
          { module: "Pricing", entity: "Community", entity_id: "1", changed_by: "Admin User", old_value: "price_min: 11800000", new_value: "price_min: 12400000", ip: "49.207.12.1", device: "Chrome / Windows" },
          { module: "Users", entity: "User", entity_id: "2", changed_by: "Admin User", old_value: "active: false", new_value: "active: true", ip: "49.207.12.2", device: "Safari / macOS" },
          { module: "Properties", entity: "Property", entity_id: "1", changed_by: "Sales Manager", old_value: "status: Draft", new_value: "status: Published", ip: "49.207.12.3", device: "Edge / Windows" },
          { module: "Builders", entity: "Builder", entity_id: "1", changed_by: "Admin User", old_value: "rating: 4.6", new_value: "rating: 4.7", ip: "49.207.12.4", device: "Chrome / Android" },
          { module: "Settings", entity: "HomepageSetting", entity_id: "1", changed_by: "Content Editor", old_value: "investors_label: 850+ Investors", new_value: "investors_label: 900+ Investors", ip: "49.207.12.5", device: "Chrome / Windows" },
        ]
        rows.each { |row| App::Models::AuditLog.create(row) }
        puts "Seeded audit logs: #{App::Models::AuditLog.count}"
      end

      # =======================================================================
      # 36-37. Notifications / Media Items — no validation issues.
      # =======================================================================
      def seed_notifications!
        SD.seed_notifications!
      end

      def seed_media_items!
        SD.seed_media_items!
        keep_first!(App::Models::MediaItem, 5)
        puts "Trimmed media items: #{App::Models::MediaItem.count}"
      end

      # =======================================================================
      # 38. Follow Ups — new table.
      # =======================================================================
      def seed_follow_ups!
        leads = App::Models::Lead.order(:id).all
        properties = App::Models::Property.order(:id).all
        agents = App::Models::Agent.order(:id).all
        rows = [
          { lead: leads[0], property: properties[0], agent: agents[0], due_date: Date.today + 2, type: "Call", priority: "High", done: false, notes: "Confirm site visit slot." },
          { lead: leads[1], property: properties[1], agent: agents[0], due_date: Date.today + 5, type: "Email", priority: "Medium", done: false, notes: "Send updated pricing sheet." },
          { lead: leads[2], property: properties[2], agent: agents[1], due_date: Date.today - 1, type: "WhatsApp", priority: "Medium", done: false, notes: "Follow up on warehouse lease terms." },
          { lead: leads[3], property: properties[3], agent: agents[2], due_date: Date.today + 1, type: "Call", priority: "Low", done: true, notes: "Post-booking welcome call completed." },
          { lead: leads[4], property: properties[4], agent: agents[3], due_date: Date.today + 7, type: "Meeting", priority: "High", done: false, notes: "In-person portfolio review." },
        ]
        rows.each do |row|
          App::Models::FollowUp.create do |f|
            f.client_name = row[:lead].client_name
            f.lead_id = row[:lead]&.id
            f.property_id = row[:property]&.id
            f.agent_id = row[:agent]&.id
            f.due_date = row[:due_date]
            f.type = row[:type]
            f.priority = row[:priority]
            f.done = row[:done]
            f.notes = row[:notes]
          end
        end
        puts "Seeded follow ups: #{App::Models::FollowUp.count}"
      end

      # =======================================================================
      # 39. Approvals — new table. Generic type/entity/entity_id shape per
      #    migrations/0041's own comment.
      # =======================================================================
      def seed_approvals!
        rows = [
          { type: "Testimonial", title: "New testimonial from Srinivas Rao", requested_by: "Sneha Rao", status: "Pending", entity: "Testimonial", entity_id: "5" },
          { type: "Pricing", title: "Bulk pricing update - Sobha Royal Crest", requested_by: "Rahul Sharma", status: "Pending", entity: "Community", entity_id: "3" },
          { type: "Blog", title: "Publish: RERA Checklist for Buyers", requested_by: "Priya Reddy", status: "Approved", entity: "Blog", entity_id: "3" },
          { type: "Refund", title: "Refund request - Aditya Rane", requested_by: "Arjun Varma", status: "Pending", entity: "Refund", entity_id: "2" },
          { type: "Agent Registration", title: "New agent self-registration - Kavya Iyer", requested_by: "Kavya Iyer", status: "Approved", entity: "Agent", entity_id: "5" },
        ]
        rows.each { |row| App::Models::Approval.create(row) }
        puts "Seeded approvals: #{App::Models::Approval.count}"
      end

      # =======================================================================
      # 40. Reviews — new table. `reviewable_type`/`reviewable_id` is a
      #    polymorphic pointer (no DB-level FK, per migrations/0046's comment).
      # =======================================================================
      def seed_reviews!
        clients = App::Models::Client.order(:id).all
        agents = App::Models::Agent.order(:id).all
        rows = [
          { client: clients[0], reviewable_type: "Agent", reviewable_id: agents[0].id, stars: 5, quote: "Rahul was extremely responsive throughout the buying process.", status: "Approved" },
          { client: clients[1], reviewable_type: "Property", reviewable_id: App::Models::Property.order(:id).all[0].id, stars: 5, quote: "Beautiful unit, exactly as described.", status: "Approved" },
          { client: clients[2], reviewable_type: "Builder", reviewable_id: App::Models::Builder.order(:id).first.id, stars: 4, quote: "Good build quality, minor delays in handover.", status: "Pending" },
          { client: clients[3], reviewable_type: "Community", reviewable_id: App::Models::Community.order(:id).first.id, stars: 5, quote: "Loved the clubhouse and green spaces.", status: "Approved" },
          { client: clients[4], reviewable_type: "RamMember", reviewable_id: App::Models::RamMember.order(:id).first.id, stars: 4, quote: "Helpful RAM, quick response time.", status: "Pending" },
        ]
        rows.each do |row|
          App::Models::Review.create do |r|
            r.client_id = row[:client].id
            r.reviewable_type = row[:reviewable_type]
            r.reviewable_id = row[:reviewable_id]
            r.stars = row[:stars]
            r.quote = row[:quote]
            r.status = row[:status]
          end
        end
        puts "Seeded reviews: #{App::Models::Review.count}"
      end

      # =======================================================================
      # 41. Notification Reads — new table.
      # =======================================================================
      def seed_notification_reads!
        notifications = App::Models::Notification.order(:id).all
        clients = App::Models::Client.order(:id).all
        rows = [
          { notification: notifications[0], recipient_type: "client", recipient_id: clients[0].id },
          { notification: notifications[1], recipient_type: "client", recipient_id: clients[1].id },
          { notification: notifications[2], recipient_type: "agent", recipient_id: App::Models::Agent.order(:id).first.id },
          { notification: notifications[3], recipient_type: "ram", recipient_id: App::Models::RamMember.order(:id).first.id },
          { notification: notifications[4], recipient_type: "client", recipient_id: clients[2].id },
        ]
        rows.each do |row|
          App::Models::NotificationRead.find_or_create(
            notification_id: row[:notification].id, recipient_type: row[:recipient_type], recipient_id: row[:recipient_id]
          )
        end
        puts "Seeded notification reads: #{App::Models::NotificationRead.count}"
      end

      # =======================================================================
      # 42. Recommendations — new table.
      # =======================================================================
      def seed_recommendations!
        clients = App::Models::Client.order(:id).all
        properties = App::Models::Property.order(:id).all
        rows = [
          { client: clients[0], property: properties[0], sender_type: "ram", sender_slug: "ram1", priority: "High", status: "Sent" },
          { client: clients[1], property: properties[1], sender_type: "agent", sender_slug: "rahul-sharma", priority: "Medium", status: "Viewed" },
          { client: clients[2], property: properties[2], sender_type: "ram", sender_slug: "ram2", priority: "High", status: "Interested" },
          { client: clients[3], property: properties[3], sender_type: "agent", sender_slug: "priya-reddy", priority: "Low", status: "Sent" },
          { client: clients[4], property: properties[4], sender_type: "ram", sender_slug: "ram3", priority: "Medium", status: "Booked" },
        ]
        rows.each do |row|
          App::Models::Recommendation.create do |r|
            r.client_id = row[:client].id
            r.property_id = row[:property].id
            r.client_name = row[:client].name
            r.client_phone = row[:client].phone
            r.property_slug = row[:property].slug
            r.property_title = row[:property].title
            r.sender_type = row[:sender_type]
            r.sender_slug = row[:sender_slug]
            r.priority = row[:priority]
            r.status = row[:status]
            r.expected_budget = row[:property].price
          end
        end
        puts "Seeded recommendations: #{App::Models::Recommendation.count}"
      end

      # =======================================================================
      # 43. Documents — new table.
      # =======================================================================
      def seed_documents!
        clients = App::Models::Client.order(:id).all
        properties = App::Models::Property.order(:id).all
        categories = ["Agreement", "Certificate", "Receipt"]

        clients.each_with_index do |client, i|
          category = categories[i % categories.length]
          App::Models::Document.create do |d|
            d.client_id = client.id
            d.property_id = properties[i]&.id
            d.client_name = client.name
            d.name = "#{category} - #{client.name}"
            d.category = category
            d.src = "data:application/pdf;base64,U0VFRA=="
            d.status = i.even? ? "Verified" : "Pending"
          end
        end
        puts "Seeded documents: #{App::Models::Document.count}"
      end

      # =======================================================================
      # 44. Saved Properties — new table. Unique on [client_id, property_id,
      #    kind] — every row below uses a distinct combination.
      # =======================================================================
      def seed_saved_properties!
        clients = App::Models::Client.order(:id).all
        properties = App::Models::Property.order(:id).all
        rows = [
          { client: clients[0], property: properties[0], kind: "saved" },
          { client: clients[0], property: properties[1], kind: "shortlist" },
          { client: clients[1], property: properties[2], kind: "saved" },
          { client: clients[2], property: properties[3], kind: "shortlist" },
          { client: clients[3], property: properties[4], kind: "saved" },
        ]
        rows.each do |row|
          App::Models::SavedProperty.find_or_create(client_id: row[:client].id, property_id: row[:property].id, kind: row[:kind])
        end
        puts "Seeded saved properties: #{App::Models::SavedProperty.count}"
      end

      # =======================================================================
      # 45. Price Histories — new table.
      # =======================================================================
      def seed_price_histories!
        App::Models::Community.order(:id).all.each_with_index do |c, i|
          App::Models::PriceHistory.create do |p|
            p.community_id = c.id
            p.price_min = c.price_min
            p.price_max = c.price_max
            p.growth_pct = c.growth_pct
            p.change_type = i.even? ? "manual" : "bulk"
            p.changed_by = "Admin User"
            p.notes = "Quarterly pricing review"
          end
        end
        puts "Seeded price histories: #{App::Models::PriceHistory.count}"
      end

      # =======================================================================
      # 46. Job Applications — new table.
      # =======================================================================
      def seed_job_applications!
        job_openings = App::Models::JobOpening.order(:id).all
        rows = [
          { job: job_openings[0], name: "Ramesh Kumar", email: "ramesh.kumar@example.com", phone: "9812340001", status: "New" },
          { job: job_openings[1], name: "Divya Menon", email: "divya.menon@example.com", phone: "9812340002", status: "Shortlisted" },
          { job: job_openings[2], name: "Aakash Verma", email: "aakash.verma@example.com", phone: "9812340003", status: "New" },
          { job: job_openings[3], name: "Sowmya Reddy", email: "sowmya.reddy@example.com", phone: "9812340004", status: "Rejected" },
          { job: job_openings[4], name: "Vishal Nair", email: "vishal.nair@example.com", phone: "9812340005", status: "Hired" },
        ]
        rows.each do |row|
          App::Models::JobApplication.create do |j|
            j.job_opening_id = row[:job]&.id
            j.name = row[:name]
            j.email = row[:email]
            j.phone = row[:phone]
            j.status = row[:status]
          end
        end
        puts "Seeded job applications: #{App::Models::JobApplication.count}"
      end

      # =======================================================================
      # 47. Newsletter Subscribers — new table.
      # =======================================================================
      def seed_newsletter_subscribers!
        rows = [
          { email: "newsletter1@example.com", status: "Subscribed", source: "Website" },
          { email: "newsletter2@example.com", status: "Subscribed", source: "Footer" },
          { email: "newsletter3@example.com", status: "Unsubscribed", source: "Website" },
          { email: "newsletter4@example.com", status: "Subscribed", source: "Blog" },
          { email: "newsletter5@example.com", status: "Subscribed", source: "Website" },
        ]
        rows.each do |row|
          App::Models::NewsletterSubscriber.find_or_create(email: row[:email]) do |n|
            n.status = row[:status]
            n.source = row[:source]
          end
        end
        puts "Seeded newsletter subscribers: #{App::Models::NewsletterSubscriber.count}"
      end

      # =======================================================================
      # 48. Contact Messages — new table.
      # =======================================================================
      def seed_contact_messages!
        rows = [
          { name: "Rakesh Bhalla", phone: "9812345601", email: "rakesh.bhalla@example.com", message: "Interested in villas near Kokapet, please call me back.", read: false },
          { name: "Sunita Verma", phone: "9812345602", email: "sunita.verma@example.com", message: "What is the possession timeline for Brigade Horizon?", read: true },
          { name: "Ganesh Iyer", phone: "9812345603", email: "ganesh.iyer@example.com", message: "Do you have any commercial listings in Gachibowli?", read: false },
          { name: "Ananya Krishnan", phone: "9812345604", email: "ananya.krishnan@example.com", message: "Referred by Kiran Kumar Reddy - please share pricing for Sobha Royal Crest.", referral_code: "REF-ANANYA", read: false },
          { name: "Farheen Ali", phone: "9812345605", email: "farheen.ali@example.com", message: "Looking for a 2 BHK under 70 lakhs in Miyapur.", read: true },
        ]
        rows.each { |row| App::Models::ContactMessage.create(row) }
        puts "Seeded contact messages: #{App::Models::ContactMessage.count}"
      end

      # =======================================================================
      # Orchestrator — truncate everything, then reseed in FK-dependency
      # order (matches ALL_TABLES above).
      # =======================================================================
      def run!
        truncate_all!

        puts "== Phase 1: Roles / Users =="
        seed_roles!
        seed_users!

        puts "== Phase 2: Property Catalog =="
        seed_builders!
        seed_property_types!
        seed_areas_and_locations!
        seed_amenities!
        seed_property_tags!
        seed_communities!
        seed_properties!
        seed_collections!

        puts "== Phase 3: CRM + Agent Network =="
        # Agents/RAM members must exist before Clients: Client#validate checks
        # assigned_agent_slug/assigned_ram_id against real Agent/RamMember
        # rows unconditionally on every new record (see RAM_SLUG_BY_MOCK_ID
        # note above) — seeding Clients first would silently produce zero
        # rows via raise_on_save_failure=false, same failure mode as the
        # ram_id mock_id mismatch this fixes.
        seed_agents!
        seed_ram_members!
        seed_portfolio_members!
        seed_clients!
        seed_leads!
        seed_site_visits!
        seed_referral_links!
        seed_referrals!
        seed_deals!
        seed_commissions!

        puts "== Phase 4: Finance =="
        seed_expenses!
        seed_invoices!
        seed_payments!
        seed_refunds!
        seed_taxes!

        puts "== Phase 5: Marketing / CMS =="
        seed_blogs!
        seed_testimonials!
        seed_faqs!
        seed_job_openings!
        seed_career_benefits!
        seed_seo_pages!
        seed_hero_stats!
        seed_homepage_settings!

        puts "== Phase 6: Ops / Logs =="
        seed_audit_logs!
        seed_notifications!
        seed_media_items!
        seed_follow_ups!
        seed_approvals!
        seed_reviews!
        seed_notification_reads!
        seed_recommendations!
        seed_documents!
        seed_saved_properties!
        seed_price_histories!
        seed_job_applications!
        seed_newsletter_subscribers!
        seed_contact_messages!

        puts "== ALL PHASES COMPLETE — #{ALL_TABLES.size} tables reset and reseeded with 5 rows each =="
      end
    end
  end
end
