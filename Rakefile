require './src/app'
namespace :db do
  desc "Run migrations"
  task :migrate, [:version] do |t, args|
    puts args, App.db_url
    require "sequel/core"
    Sequel.extension :migration
    version = args[:version].to_i if args[:version]
    puts version
    Sequel.connect(App.db_url) do |db|
      db.extension :pg_enum
      Sequel::Migrator.run(db, "src/migrations", target: version)
    end
  end
end


require 'optparse'


namespace :create do
  desc "Creates Model"
  task :models do #|t, args|
    models = []
    OptionParser.new do |opts|
      puts opts
      opts.banner = "Usage: rake create:models [options]"
      opts.on("-n", "--names ARG", String) { |str| models += str.split(',') }

    end.parse!
    puts models
    exit
  end
end

namespace :db do
  desc "Seed default roles and a bootstrap super-admin user (idempotent)"
  task :seed do
    App.load!

    role = App::Models::Role.find_or_create(slug: 'role-super-admin') do |r|
      r.name = 'Super Admin'
      r.level = 0
      r.is_super_admin = true
      r.status = 'Active'
      r.description = 'Full, unrestricted access to every module.'
      r.permissions = Sequel.pg_array(['*'])
    end

    seed_email = ENV['SEED_ADMIN_EMAIL'] || 'admin@rerockrealty.com'
    seed_password = ENV['SEED_ADMIN_PASSWORD'] || 'ChangeMe123!'

    user = App::Models::User.find(email: seed_email)
    if user.nil?
      user = App::Models::User.new(
        full_name: 'Super Admin',
        email: seed_email,
        role_id: role.id,
        is_super_admin: true,
        active: true
      )
      user.password = seed_password
      user.save
      puts "Seeded bootstrap admin: #{seed_email} / #{seed_password} (change this password after first login)"
    else
      puts "Bootstrap admin #{seed_email} already exists, skipped."
    end
  end

  desc "Seed full sample/demo data (idempotent) into every real table"
  task :seed_sample_data do
    App.load!
    require './src/seeds/sample_data'
    App::Seeds::SampleData.run!
  end
end

namespace :db do
  desc "UAT reset: TRUNCATE every table (RESTART IDENTITY CASCADE) and reseed exactly 5 rows into each"
  task :reset_and_reseed_uat do
    App.load!
    require './src/seeds/reset_and_reseed'
    App::Seeds::ResetAndReseed.run!
  end
end

namespace :db do
  # Read-only — never mutates anything. Reports exactly which rows have a
  # stale reference inside the Property Catalog's array-of-ids columns
  # (communities.amenity_ids, properties.amenity_ids/tag_ids,
  # collections.property_ids — none of these have a DB-level FK, so a
  # deleted Amenity/PropertyTag/Property can silently leave a dangling id
  # behind) plus properties.agent_slug values that no longer match a real
  # Agent. Run before relying on the new model-level existence validation
  # (models/community.rb#validate_amenity_ids, models/property.rb#
  # validate_amenity_and_tag_ids) to catch anything already in the table —
  # those only fire on a future save, not on rows nobody edits again.
  desc "Report (do not repair) stale amenity_ids/tag_ids/property_ids/agent_slug references in the Property Catalog"
  task :audit_property_catalog_references do
    App.load!

    valid_amenity_ids = App::Models::Amenity.select_map(:id).to_set
    valid_tag_ids = App::Models::PropertyTag.select_map(:id).to_set
    valid_property_ids = App::Models::Property.select_map(:id).to_set
    valid_agent_slugs = App::Models::Agent.select_map(:slug).to_set

    puts "== Communities: invalid amenity_ids =="
    App::Models::Community.select(:id, :name, :amenity_ids).each do |c|
      bad = (c.amenity_ids || []) - valid_amenity_ids.to_a
      puts "  Community ##{c.id} (#{c.name}): #{bad.join(', ')}" if bad.any?
    end

    puts "== Properties: invalid amenity_ids =="
    App::Models::Property.select(:id, :title, :amenity_ids).each do |p|
      bad = (p.amenity_ids || []) - valid_amenity_ids.to_a
      puts "  Property ##{p.id} (#{p.title}): #{bad.join(', ')}" if bad.any?
    end

    puts "== Properties: invalid tag_ids =="
    App::Models::Property.select(:id, :title, :tag_ids).each do |p|
      bad = (p.tag_ids || []) - valid_tag_ids.to_a
      puts "  Property ##{p.id} (#{p.title}): #{bad.join(', ')}" if bad.any?
    end

    puts "== Collections: invalid property_ids =="
    App::Models::Collection.select(:id, :name, :property_ids).each do |c|
      bad = (c.property_ids || []) - valid_property_ids.to_a
      puts "  Collection ##{c.id} (#{c.name}): #{bad.join(', ')}" if bad.any?
    end

    puts "== Properties: agent_slug not matching any real Agent =="
    App::Models::Property.exclude(agent_slug: nil).select(:id, :title, :agent_slug).each do |p|
      puts "  Property ##{p.id} (#{p.title}): agent_slug=#{p.agent_slug.inspect}" unless valid_agent_slugs.include?(p.agent_slug)
    end

    puts "Done. Any rows listed above have a stale/orphaned reference — nothing was changed."
  end
end


# DATABASE_URL="postgres://doqhgpwk:faHZB60XTVMZTczxkznkvXC0rcHxyap6@rogue.db.elephantsql.com:5432/doqhgpwk" rake db:migrate\[0\]


# DATABASE_URL="postgres://exbkkjhk:teWF4qtJwyLZMXLm0CDM1eiYfNC-xr_T@satao.db.elephantsql.com:5432/exbkkjhk" rake db:migrate\[7\]
# DATABASE_URL="postgres://lnhtywgf:qfdIK2eJVhJlES3jAsyU4wZAxx1ESzfi@balarama.db.elephantsql.com:5432/lnhtywgf" rake db:migrate