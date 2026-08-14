require "dotenv/load"
require "sequel"
require "bundler/setup"
require "active_support/all"
require "bcrypt"
require "logger"
require "aws-sdk-s3"
module App
  class<<self
    attr_reader :db, :audit_db
    # Was hardcoded to 1 — Puma defaults to up to 5 request-handling threads,
    # and the admin Dashboard alone fires ~15 API calls in parallel on mount,
    # each needing a connection for both its own query and the per-request
    # CurrentUser#user_obj auth lookup. With only 1 connection, concurrent
    # requests queue behind each other and can hit Sequel's default 5s
    # pool_timeout — which user_obj below was silently swallowing as "no such
    # user", incorrectly 401ing a perfectly valid session under load.
    NUMBER_OF_CONNECTIONS = (ENV['POOL_SIZE'] || 10).to_i
    
    def development?
      env == 'development'
    end

    def logger
      @logger ||= Logger.new(STDOUT)
    end

    def env
      @env ||= ENV['RACK_ENV'] || 'development'
    end

    def root
      @root ||= File.expand_path(File.dirname(__FILE__) + '/../')
    end

    def require_blob(blb)
      Dir[File.join(root, 'src', blb)].each {|f| require f}
    end

    def db_url
      ENV['DB_URL'] 
    end

    def load!
      # First connect to the database
      connect_to_database
      
      # Load libraries before models
      require_blob('lib/**/*.rb')
      
      # Setup Sequel configuration
      setup_sequel!
      
      # Load helpers before models
      App.require_blob('helpers/*.rb')
      
      # Load models in the correct order
      require_blob('models/concerns/*.rb')
      require_blob('models/*.rb')
      require_blob('models/**/*.rb')
      
      # Load routes last
      require_relative 'routes'

      # Configure AWS with environment variables
      setup_aws_config
    end

    def connect_to_database
      @db = Sequel.connect(db_url, 
        max_connections: NUMBER_OF_CONNECTIONS, 
        logger: logger, 
        after_connect: Proc.new { logger.info("Database connection established") }
      )
      @db.extension(:connection_validator)
      @db.pool.connection_validation_timeout = 3600
    end
    
    def setup_aws_config
      # Use environment variables instead of hardcoded credentials
      aws_access_key = ENV['AWS_ACCESS_KEY_ID']
      aws_secret_key = ENV['AWS_SECRET_ACCESS_KEY']
      aws_region = ENV['AWS_REGION'] || 'ap-south-1'
      
      Aws.config.update(
        region: aws_region,
        credentials: Aws::Credentials.new(aws_access_key, aws_secret_key),
      )
      
      logger.info("AWS configuration initialized for region: #{aws_region}")
    end

    def cu
      App::Helpers::CurrentUser
    end

    def generate_id
      Time.now.utc.strftime("%Y%m%d%k%M%S%L%N").to_i.to_s(36)
    end

    def setup_sequel!
      Sequel::Model.plugin :validation_helpers
      Sequel::Model.plugin :force_encoding, 'UTF-8'
      Sequel::Model.plugin(::SequelPlugin::SaveUserId)
      # Sequel::Model.plugin(::SequelPlugin::JsonValuesValidations)
      # Sequel::Model.plugin(::SequelPlugin::JsonValueTypecast)
      Sequel::Model.plugin(::SequelPlugin::DefaultJson)
      Sequel::Model.plugin :nested_attributes
      Sequel::Model.plugin :dirty
      Sequel::Model.plugin :json_serializer
      Sequel::Model.raise_on_save_failure = false
      Sequel.extension :core_extensions
      Sequel.extension :named_timezones
      Sequel.extension :pg_json_ops
      Sequel.extension :pg_array_ops
      db.extension :pg_json, :pg_array, :pg_enum
      db.wrap_json_primitives = true
      db.typecast_json_strings = true
    end
  end

  module Models
  end
  module Services
  end
  module Helpers; end
  module Router; end
end

# db_url = "postgres://appadmin:dev123@172.16.169.228:5432/lnhtywgf"



# postgres://qxkzecte:7KET4hfRlDfexuBw7DnXm2mTFdXILqoG@satao.db.elephantsql.com/qxkzecte

# max_id = DB[:users].max(:id)

# # Set the sequence to the maximum id + 1
# DB.run("SELECT setval(pg_get_serial_sequence('users', 'id'), #{max_id + 1})")