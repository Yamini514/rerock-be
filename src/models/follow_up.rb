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

  # Real, computed live from due_date vs today rather than a stored column.
  # Was private to services/follow_ups.rb#list; moved here so
  # services/agent_portal.rb#my_follow_ups (the agent-scoped read) can
  # compute the exact same "overdue" flag instead of duplicating the logic.
  def with_overdue
    to_pos.merge('overdue' => !done && !due_date.nil? && due_date < Date.today)
  end
end
