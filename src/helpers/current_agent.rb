class App::Helpers::CurrentAgent
  # Deliberately a *different* secret from CurrentUser/CurrentRam/CurrentClient
  # — an Agent Portal token must never be replayable as any of the other
  # three. Same "wholly separate identity, wholly separate class" reasoning
  # as helpers/current_ram.rb and helpers/current_client.rb.
  SECRET = "016b6a92-3d78-4f6a-9b7e-agent-portal-a1b2c3d4e5f6a7b8c9d0"
  TOKEN_EXPIRY = 180 * 60 * 60

  class << self
    def id
      decoded_token&.[](:agent_id)
    end

    def valid?
      return false if id.blank? || agent_obj.nil?

      agent_obj.current_session_id == token
    end

    def token
      auth_token = space[:auth_token]
      return nil if auth_token.nil? || auth_token.empty?
      space[:agent_token] ||= auth_token.sub(/\ABearer\s+/, "")
    end

    def space
      Thread.current[:app_space] || {}
    end

    def decoded_token
      return nil if token.nil?

      space[:agent_decoded] ||= begin
        decoded = JWT.decode(token, SECRET, true, { algorithm: 'HS256' })[0].with_indifferent_access

        if decoded[:exp] && Time.now.to_i > decoded[:exp]
          App.logger.warn("Agent token expired for agent #{decoded[:agent_id]}")
          return nil
        end

        decoded
      rescue JWT::DecodeError, JWT::VerificationError
        nil
      rescue => e
        App.logger.error("Agent token decode error: #{e.message}")
        nil
      end
    end

    def agent_obj
      return nil if id.blank?

      space[:agent_obj] ||= begin
        agent = App::Models::Agent[id]
        App.logger.warn("Agent not found: #{id}") if agent.nil?
        agent
      rescue Sequel::PoolTimeoutError, Sequel::DatabaseConnectionError => e
        App.logger.error("DB unavailable while fetching agent #{id}: #{e.message}")
        raise
      rescue => e
        App.logger.error("Error fetching agent: #{e.message}")
        nil
      end
    end

    def encoded_token(agent)
      exp = (Time.now + TOKEN_EXPIRY).to_i
      payload = { agent_id: agent.id, exp: exp, iat: Time.now.to_i }
      JWT.encode(payload, SECRET, 'HS256')
    end
  end
end
