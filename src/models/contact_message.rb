class App::Models::ContactMessage < Sequel::Model
  EMAIL_REGEXP = /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/

  def validate
    super
    validates_presence [:name, :message]
    validates_format(EMAIL_REGEXP, :email, message: 'is not a valid email address') if email.present?
  end
end
