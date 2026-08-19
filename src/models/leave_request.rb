class App::Models::LeaveRequest < Sequel::Model
  many_to_one :agent

  STATUSES = %w[Pending Approved Rejected Cancelled].freeze
  TYPES = ['Leave', 'Half Day'].freeze

  def validate
    super
    validates_presence [:agent_id, :start_date, :end_date]
    errors.add(:end_date, 'must be on or after the start date') if start_date && end_date && end_date < start_date
  end

  # One date string per calendar day in [start_date, end_date] — used by
  # #apply_to_attendance! below.
  def date_range
    (start_date..end_date).map(&:to_s)
  end

  # Fired from services/leave_requests.rb#update only when the caller has
  # already determined `status` just changed to "Approved" — same "compute
  # *_changing before save, act after" convention as
  # Lead#notify_agent_of_assignment!. Appends a `{date, status}` attendance
  # row for every day in range that doesn't already have one; never
  # overwrites a day already marked (same rule as
  # AgentAuth#mark_attendance_present!), so an admin's own prior manual entry
  # for that day always wins.
  def apply_to_attendance!
    existing_dates = (agent.attendance || []).map { |a| a['date'] }
    new_rows = date_range.reject { |d| existing_dates.include?(d) }.map { |d| { 'date' => d, 'status' => leave_type } }
    return if new_rows.empty?

    agent.attendance = (agent.attendance || []) + new_rows
    agent.save_changes(validate: false)
  end

  def notify_admin_of_request!
    App::Models::Notification.create(
      audience: 'admin',
      type: 'leave',
      icon: 'CalendarOff',
      title: 'New leave request',
      message: "#{agent.name} requested #{leave_type.downcase} from #{start_date.strftime('%d %b')} to #{end_date.strftime('%d %b')}."
    )
  end

  def notify_agent_of_decision!
    App::Models::Notification.create(
      audience: 'agent',
      recipient_id: agent_id,
      type: 'leave',
      icon: status == 'Approved' ? 'CheckCircle2' : 'XCircle',
      title: "Leave request #{status.downcase}",
      message: "Your leave request (#{start_date.strftime('%d %b')} – #{end_date.strftime('%d %b')}) was #{status.downcase}#{decision_note.present? ? ": #{decision_note}" : '.'}"
    )
  end
end
