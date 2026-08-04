class App::Helpers::CurrentClient
  # Deliberately a *different* secret from CurrentUser::SECRET and
  # CurrentRam::SECRET — a Client Portal token must never be replayable as an
  # admin or RAM Portal token, or vice versa. Same "wholly separate identity,
  # wholly separate class" reasoning as helpers/current_ram.rb: Client isn't
  # a User (no role_id/staff?) and isn't a RamMember; admin_required!/
  # auth_required!/ram_auth_required! are each written against exactly one
  # of the three. See routes.rb's client_auth_required! for the route guard
  # this backs.
  SECRET = "6ba7b810-9dad-11d1-80b4-00c04fd430c8-client-portal-1b671a64-40d5"
  TOKEN_EXPIRY = 180 * 60 * 60

  class << self
    def id
      decoded_token&.[](:client_id)
    end

    def valid?
      return false if id.blank? || client_obj.nil?

      client_obj.current_session_id == token
    end

    def token
      auth_token = space[:auth_token]
      return nil if auth_token.nil? || auth_token.empty?
      space[:client_token] ||= auth_token.sub(/\ABearer\s+/, "")
    end

    def space
      Thread.current[:app_space] || {}
    end

    def decoded_token
      return nil if token.nil?

      space[:client_decoded] ||= begin
        decoded = JWT.decode(token, SECRET, true, { algorithm: 'HS256' })[0].with_indifferent_access

        if decoded[:exp] && Time.now.to_i > decoded[:exp]
          App.logger.warn("Client token expired for client #{decoded[:client_id]}")
          return nil
        end

        decoded
      rescue JWT::DecodeError, JWT::VerificationError
        # An admin or RAM token decoded here raises exactly this — expected
        # and silent, same reasoning as current_ram.rb's identical rescue.
        nil
      rescue => e
        App.logger.error("Client token decode error: #{e.message}")
        nil
      end
    end

    def client_obj
      return nil if id.blank?

      space[:client_obj] ||= begin
        client = App::Models::Client[id]
        App.logger.warn("Client not found: #{id}") if client.nil?
        client
      rescue Sequel::PoolTimeoutError, Sequel::DatabaseConnectionError => e
        App.logger.error("DB unavailable while fetching client #{id}: #{e.message}")
        raise
      rescue => e
        App.logger.error("Error fetching client: #{e.message}")
        nil
      end
    end

    def encoded_token(client)
      exp = (Time.now + TOKEN_EXPIRY).to_i
      payload = { client_id: client.id, exp: exp, iat: Time.now.to_i }
      JWT.encode(payload, SECRET, 'HS256')
    end
  end
end
