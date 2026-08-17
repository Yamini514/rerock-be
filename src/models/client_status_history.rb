class App::Models::ClientStatusHistory < Sequel::Model
  many_to_one :client

  def validate
    super
    validates_presence [:client_id, :status]
  end
end
