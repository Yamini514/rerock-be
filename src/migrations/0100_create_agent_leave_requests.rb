Sequel.migration do
  change do
    # Agent-initiated leave requests, reviewed by an admin — see
    # services/agent_portal.rb#create_my_leave_request (creation) and
    # services/leave_requests.rb#update (approve/reject). A real `agent_id`
    # FK, same convention as follow_ups (migrations/0040) rather than the
    # older deferred `agent_slug` string used by Deals/Leads/SiteVisits.
    create_table(:agent_leave_requests) do
      primary_key :id

      foreign_key :agent_id, :agents, null: false

      Date :start_date, null: false
      Date :end_date, null: false
      # Matches the existing Agent#attendance status vocabulary exactly
      # (AgentDetailClient.js's attendanceTone: Present/Half Day/Leave) so
      # an approved request's `leave_type` can be written straight into an
      # attendance row's `status` with no translation step — see
      # LeaveRequest#apply_to_attendance!.
      String :leave_type, default: 'Leave'
      String :reason, text: true

      String :status, default: 'Pending'
      String :decision_note, text: true
      # Name string, not a user id — same "changed_by" convention as
      # LeadStatusHistory/ClientStatusHistory/DealStatusHistory (see
      # services/base.rb#audit_changed_by), not an admin `users.id` FK.
      String :decided_by
      DateTime :decided_at

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :agent_id
      index :status
      index :start_date
    end
  end
end
