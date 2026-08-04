class App::Services::Users < App::Services::Base
  def model; User; end

  RESET_TOKEN_EXPIRATION_TIME = 2 * 60 * 60 

  def list
    ds = model.order(Sequel.desc(:created_at))
    if qs[:search].present?
      ds = ds.where(Sequel.like(:full_name, "%#{qs[:search]}%", case_insensitive: true)).or(Sequel.like(:phone_number, "%#{qs[:search]}%"))
    end
    count = ds.count
    return_success(ds.offset(offset).limit(limit).all.map(&:as_pos), total_pages: (count / page_size.to_f).ceil )
  end


  def get
    return_success(item.as_pos)
  end

  def create
    obj = model.new(data_for(:save))
    save(obj) { |o| return_success(o.as_pos) }
  end

  # Overrides Base#update/#delete purely for response shape: Base's versions
  # return `item.to_pos` (DefaultJson's generic as_json-of-every-column dump),
  # which would leak `encoded_password`/`current_session_id`/etc. straight to
  # the browser. Every other Users response (list/get/create/info) already
  # goes through the custom `as_pos` below — this closes the same gap on
  # update/delete now that the admin Users page actually calls them for real.
  def update(data = nil)
    data ||= data_for(:save)
    item.set_fields(data, data.keys)
    save(item) { |o| return_success(o.as_pos) }
  end

  def delete
    res = item.delete
    res ? return_success(res.as_pos) : return_errors!('Unable to delete')
  rescue => e
    App.logger.error(e.message)
    App.logger.error(e.backtrace)
    return_errors!(e.message, 400)
  end

  def info
    return_success(App.cu.user_obj.as_pos)
  end

  def update_password
    
    if App.cu.user_obj.password == params[:current_password]
      u = App.cu.user_obj
      u.password = params[:new_password]
      save(u) do |u|
        return_success("successfully updated password!!")
      end
    else
      return_errors!("Invalid password!!")
    end
  end

  def forgot_password
    email = params[:email]
    if email.present?
      user = App::Models::User.where(email: email).first
      if user
        user.send_password_reset_email(ENV['ADMIN_APP_URL'] || 'http://localhost:3000/admin')
        return_success("Password reset email sent to #{user.email}")
      else
        return_errors("User not found with email: #{email}", 404)
      end
    else
      return_errors("User email is required!", 400)
    end
  end


  def validate_password_token
    token = params['token']
    
    if token.nil? || token.empty?
      return_errors!('Token is missing.', 400)
    else
      user = App::Models::User.where(reset_token: token).first
      if user && token_valid?(user)
        return_success('Token is valid.')
      else
        return_errors!('Invalid or expired token.')
      end
    end
  end

  def token_valid?(user)
    return false if user.reset_sent_at.nil?
  
    token_age = Time.now - user.reset_sent_at
    token_age < RESET_TOKEN_EXPIRATION_TIME
  end

  def reset_password
    token = params['token']
    new_password = params['password']

    if token.nil? || new_password.nil?
      return_errors!('Token and new password are required.', 400)
    else
      user = App::Models::User.where(reset_token: token).first
      if user && token_valid?(user)
        # Update the user's password and clear the reset token
        user.update(
          password: new_password,  # Use your password hashing logic here
          reset_token: nil,
          reset_sent_at: nil
        )
        return_success('Password has been reset.')
      else
        return_errors!('Invalid or expired token.', 400)
      end
    end
  end

  def self.fields
    {
      save: [
        :full_name, :password, :email, :role_id, :is_super_admin, :active,
        :phone_number, :designation, :department, :reporting_to_id, :permission_overrides
      ]
    }
  end
end