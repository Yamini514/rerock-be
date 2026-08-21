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

  # Same "call unconditionally after save, guard by an actual-change check"
  # convention as Lead#notify_agent_of_assignment! — fires whenever this
  # follow-up is newly created already assigned, or an existing one gets
  # (re)assigned to a different agent, called from
  # services/follow_ups.rb#create/#update.
  def notify_agent_of_assignment!
    return if agent_id.blank?
    return unless new? || column_changed?(:agent_id)

    agent = App::Models::Agent[agent_id]
    return if agent.nil?

    App::Models::Notification.create(
      audience: 'agent',
      recipient_id: agent.id,
      type: 'followup',
      icon: 'Bell',
      title: 'New follow-up assigned',
      message: "A follow-up has been assigned to you: #{client_name}."
    )
    agent.log_activity!(title: 'Follow-up assigned', description: "Assigned: #{client_name}")
  end
end
