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


# DATABASE_URL="postgres://doqhgpwk:faHZB60XTVMZTczxkznkvXC0rcHxyap6@rogue.db.elephantsql.com:5432/doqhgpwk" rake db:migrate\[0\]


# DATABASE_URL="postgres://exbkkjhk:teWF4qtJwyLZMXLm0CDM1eiYfNC-xr_T@satao.db.elephantsql.com:5432/exbkkjhk" rake db:migrate\[7\]
# DATABASE_URL="postgres://lnhtywgf:qfdIK2eJVhJlES3jAsyU4wZAxx1ESzfi@balarama.db.elephantsql.com:5432/lnhtywgf" rake db:migrate