class App::Services::Session < App::Services::Base

  def login
    # if current_user
    #   obj = App.cu.user_obj
    #   return_success!(token: App.cu.token, info: obj.basic_info,
    #     auth: obj.auth_data, entity_auth: obj.auth, all_roles: obj.all_roles
    #   )
    # end
    begin
      user = User.find(email: params[:email]&.strip, active: true)
      if (user && user.password == params[:password])
        if App.cu.current_did.present?
          user.device_uuid ||= App.cu.current_did
          if user.device_uuid != App.cu.current_did
            return_errors!("Not allowed to login from multiple devices. Please contact support.")
          end
        end
        user.last_logged_in_at = Time.now
        user.current_session_id = CurrentUser.encoded_token(user)
        puts "USER IP: #{App.cu.ip}"
        # user.logged_in_ips  = (user.logged_in_ips || []).prepend([App.cu.ip, Time.now]).uniq{|a| a[0]}
        # `raise_on_save_failure` is globally false (app.rb), so a failed save
        # here returns false silently rather than raising — without this
        # check, the login response still returns a 200 with a token that was
        # never actually persisted to current_session_id, and every
        # subsequent request 401s on the CurrentUser#valid? comparison below.
        unless user.save
          return_errors!(user.errors, 400)
        end
        return_success(token: user.current_session_id, info: user.as_pos)
      else
        return_errors!("Invalid Email / Password")
      end
    rescue => e
      puts e.message
      puts e.backtrace
      return_errors!("Some error!!!")
    end
  end


end