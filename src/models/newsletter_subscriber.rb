class App::Models::NewsletterSubscriber < Sequel::Model
  def validate
    super
    validates_presence [:email]
    validates_unique(:email)
  end
end
