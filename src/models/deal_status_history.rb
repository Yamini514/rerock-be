class App::Models::DealStatusHistory < Sequel::Model
  many_to_one :deal

  def validate
    super
    validates_presence [:deal_id, :status]
  end
end
