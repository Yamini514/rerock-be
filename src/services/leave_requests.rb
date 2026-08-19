# Admin review queue for agent leave requests. Real requests always
# originate from services/agent_portal.rb#create_my_leave_request — this
# service's own #create exists only so an admin can log one on an agent's
# behalf. The actual day-to-day action is #update flipping `status` to
# Approved/Rejected, which stamps who/when decided, notifies the agent, and
# (only on Approved) backfills the attendance log — same "compute
# *_changing before save, act after" convention as
# Leads#update/Lead#notify_agent_of_assignment!.
class App::Services::LeaveRequests < App::Services::Base
  def model; LeaveRequest; end

  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(agent_id: qs[:agent_id]) if qs[:agent_id].present?
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    paginated_response(ds)
  end

  def update(data = nil)
    data ||= data_for(:save)
    status_changing = data.key?(:status) && data[:status] != item.status
    data = data.merge(decided_by: audit_changed_by, decided_at: Time.now) if status_changing && data[:status] != 'Pending'
    item.set_fields(data, data.keys)
    save(item) do |o|
      o.apply_to_attendance! if status_changing && o.status == 'Approved'
      o.notify_agent_of_decision! if status_changing && %w[Approved Rejected].include?(o.status)
      return_success(o.to_pos)
    end
  end

  def self.fields
    {
      save: [:agent_id, :start_date, :end_date, :leave_type, :reason, :status, :decision_note]
    }
  end
end
