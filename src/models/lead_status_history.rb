class App::Models::LeadStatusHistory < Sequel::Model
  many_to_one :lead

  def validate
    super
    validates_presence [:lead_id, :status]
  end
end
