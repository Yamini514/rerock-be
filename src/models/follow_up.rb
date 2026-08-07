class App::Models::FollowUp < Sequel::Model
  many_to_one :lead
  many_to_one :property
  many_to_one :agent

  # Defense-in-depth under the admin Follow Ups form's own client-side
  # checks (currently the only validation that exists at all for this
  # resource).
  def validate
    super
    validates_presence [:client_name, :due_date]
  end
end
