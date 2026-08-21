class App::Helpers::CurrentUser
  SECRET = "271wsd090-d6e5-0137-5d4d-1c3676vcmnbtyd4305-2aaabcb0-d6e5-0137-5d4d-xhmrty"
  TOKEN_EXPIRY = 180 * 60 * 60
# Extracted as a constant for easier management

  class<<self
    def id
      decoded_token&.[](:id)
    end

    def role
      decoded_token&.[](:role)
    end

    def valid?
      return false if id.blank? || user_obj.nil?
      
      # Check if token matches and is not expired
      user_obj.current_session_id == token
    end

    def ip
      space[:ip]
    end

    def space
      Thread.current[:app_space] || {}
    end

    def current_did
      space[:did]
    end

    def token
      auth_token = space[:auth_token]
      return nil if auth_token.nil? || auth_token.empty?
      # Must cache into `space` (Thread.current[:app_space], reset per-request
      # by Before.clear_thread_space!), same as decoded_token/user_obj below —
      # NOT a bare @token ivar, which lives on the CurrentUser class itself
      # and would persist across every request this process ever handles,
      # letting the first request's token silently "win" for everyone after it.
      space[:token] ||= auth_token.sub(/\ABearer\s+/, "")
    end

    def decoded_token
      return nil if token.nil?

      space[:decoded] ||= begin
        decoded = JWT.decode(token, SECRET, true, { algorithm: 'HS256' })[0].with_indifferent_access
        
        # Check token expiration
        if decoded[:exp] && Time.now.to_i > decoded[:exp]
          App.logger.warn("Token expired for user #{decoded[:id]}")
          return nil
        end
        
        decoded
      rescue JWT::DecodeError, JWT::VerificationError
        # A RAM/Agent/Client Portal token (each signed with its own separate
        # SECRET — see current_ram.rb/current_agent.rb/current_client.rb)
        # fails signature verification here every time, since SaveUserId's
        # plugin (lib/plugins/save_user_id.rb) unconditionally calls
        # CurrentUser.id on every model save regardless of which portal the
        # request actually belongs to. Expected and silent, not an error
        # worth logging — same "cross-portal token decode is a normal,
        # frequent no-op" reasoning as CurrentRam/CurrentAgent/CurrentClient's
        # own decoded_token.
        nil
      rescue => e
        App.logger.error("Token decode error: #{e.message}")
        nil
      end
    end

    def user_obj
      return nil if id.blank?

      space[:user_obj] ||= begin
        user = App::Models::User.where(active: true)[id]
        App.logger.warn("User not found or inactive: #{id}") if user.nil?
        user
      rescue Sequel::PoolTimeoutError, Sequel::DatabaseConnectionError => e
        # A DB hiccup is not "this session is invalid" — swallowing it into a
        # bare `nil` here made `valid?` return false, which auth_required!
        # turns into a 401, which the frontend treats as a real logout. Let
        # this surface as a 500 instead of forcibly signing out a perfectly
        # valid session just because the connection pool was briefly maxed
        # out (see app.rb's NUMBER_OF_CONNECTIONS comment for the full story).
        App.logger.error("DB unavailable while fetching user #{id}: #{e.message}")
        raise
      rescue => e
        App.logger.error("Error fetching user: #{e.message}")
        nil
      end
    end

    def basic_info
      return {} if user_obj.nil?

      user_obj.values.slice(:email, :full_name, :role_id)
    end

    # "Admin" here means Super Admin — bypasses per-flag permission checks entirely.
    def admin?
      user_obj&.is_super_admin == true
    end

    # Staff/admin-portal user: has a role assigned at all (as opposed to a
    # plain client-portal account, which has no role_id).
    def staff?
      user_obj&.role_id.present?
    end

    def has_permission?(flag)
      return false if user_obj.nil?
      return true if admin?

      user_obj.resolved_permissions.include?(flag)
    end

    def encoded_token(user)
      exp = (Time.now + TOKEN_EXPIRY).to_i
      payload = { 
        id: user.id, 
        role: user.role, 
        ip: ip, 
        exp: exp,
        iat: Time.now.to_i # Added issued at timestamp
      }
      JWT.encode(payload, SECRET, 'HS256')
    end
    
    def clear_cache!
      space.delete(:decoded)
      space.delete(:user_obj)
      space.delete(:token)
    end
  end

  # Removed commented code
end