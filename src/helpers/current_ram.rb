class App::Helpers::CurrentRam
  # Deliberately a *different* secret from CurrentUser::SECRET — a RAM
  # Portal token must never be replayable as an admin token or vice versa.
  # Same reasoning covers why this is a wholly separate class rather than a
  # generalized "current actor" concept: RamMember isn't a User (no role_id,
  # no is_super_admin, no staff?), and admin_required!/auth_required! are
  # written specifically against App::Models::User — reusing them for a RAM
  # member's own session would either require weakening that check or
  # silently letting a RAM Portal token pass an admin gate. See routes.rb's
  # ram_auth_required! for the route guard this backs.
  SECRET = "3f2504e0-4f89-4143-a6d1-6f5c1b2f6ef0-ram-portal-9b1deb4d-3b7d-4bad"
  TOKEN_EXPIRY = 180 * 60 * 60

  class << self
    def id
      decoded_token&.[](:ram_id)
    end

    def valid?
      return false if id.blank? || ram_obj.nil?

      ram_obj.current_session_id == token
    end

    def token
      # Reads the same Authorization header Before.run! already parsed into
      # Thread.current[:app_space][:auth_token] for the admin flow — a given
      # request only ever carries one bearer token, so there's no conflict
      # in reading it here too. Cached under a RAM-specific key
      # (:ram_token, not :token) so this never collides with
      # CurrentUser's own cache of the same raw string.
      auth_token = space[:auth_token]
      return nil if auth_token.nil? || auth_token.empty?
      space[:ram_token] ||= auth_token.sub(/\ABearer\s+/, "")
    end

    def space
      Thread.current[:app_space] || {}
    end

    def decoded_token
      return nil if token.nil?

      space[:ram_decoded] ||= begin
        decoded = JWT.decode(token, SECRET, true, { algorithm: 'HS256' })[0].with_indifferent_access

        if decoded[:exp] && Time.now.to_i > decoded[:exp]
          App.logger.warn("RAM token expired for ram_member #{decoded[:ram_id]}")
          return nil
        end

        decoded
      rescue JWT::DecodeError, JWT::VerificationError
        # An admin token (signed with CurrentUser::SECRET) decoded here
        # raises exactly this — expected and silent, not an error worth
        # logging, since any admin-authenticated request will legitimately
        # hit this path once per request via ram_auth_required!'s check.
        nil
      rescue => e
        App.logger.error("RAM token decode error: #{e.message}")
        nil
      end
    end

    def ram_obj
      return nil if id.blank?

      space[:ram_obj] ||= begin
        ram = App::Models::RamMember[id]
        App.logger.warn("RAM member not found: #{id}") if ram.nil?
        ram
      rescue Sequel::PoolTimeoutError, Sequel::DatabaseConnectionError => e
        App.logger.error("DB unavailable while fetching ram_member #{id}: #{e.message}")
        raise
      rescue => e
        App.logger.error("Error fetching ram_member: #{e.message}")
        nil
      end
    end

    def encoded_token(ram)
      exp = (Time.now + TOKEN_EXPIRY).to_i
      payload = { ram_id: ram.id, exp: exp, iat: Time.now.to_i }
      JWT.encode(payload, SECRET, 'HS256')
    end
  end
end
