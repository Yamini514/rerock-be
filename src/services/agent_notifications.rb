# Agent Portal's own read-only view over admin-broadcast notifications
# targeted at audience "agent" — same shape as services/client_notifications.rb
# and services/ram_notifications.rb, kept as its own copy for the same
# "separate identity table, no shared concern" reasoning.
class App::Services::AgentNotifications < App::Services::Base
  def model; Notification; end

  def mine
    agent = CurrentAgent.agent_obj
    return_errors!("Not signed in.", 401) if agent.nil?

    return_success(notifications_with_read_state(agent.id))
  end

  # Toggles read/unread (matches components/portal/NotificationItem's
  # "Mark read"/"Mark unread" button, which always flips current state)
  # rather than only ever marking read.
  def mark_read
    agent = CurrentAgent.agent_obj
    return_errors!("Not signed in.", 401) if agent.nil?

    notification = visible_scope(agent.id).where(id: rp[:id]).first
    return_errors!("Notification not found.", 404) if notification.nil?

    existing = NotificationRead.where(notification_id: notification.id, recipient_type: "agent", recipient_id: agent.id).first
    existing ? existing.delete : NotificationRead.create(notification_id: notification.id, recipient_type: "agent", recipient_id: agent.id)
    return_success(notifications_with_read_state(agent.id))
  end

  def mark_all_read
    agent = CurrentAgent.agent_obj
    return_errors!("Not signed in.", 401) if agent.nil?

    ids = visible_scope(agent.id).select_map(:id)
    already_read = NotificationRead.where(recipient_type: "agent", recipient_id: agent.id, notification_id: ids).select_map(:notification_id)
    (ids - already_read).each { |nid| NotificationRead.create(notification_id: nid, recipient_type: "agent", recipient_id: agent.id) }

    return_success(notifications_with_read_state(agent.id))
  end

  private

  # Broadcasts (recipient_id nil) plus anything targeted at this one agent
  # specifically — never another agent's personal notification.
  def visible_scope(agent_id)
    Notification.where(audience: "agent").where(Sequel.|({ recipient_id: nil }, { recipient_id: agent_id }))
  end

  def notifications_with_read_state(agent_id)
    read_ids = NotificationRead.where(recipient_type: "agent", recipient_id: agent_id).select_map(:notification_id)
    visible_scope(agent_id).order(Sequel.desc(:created_at), Sequel.desc(:id)).all.map do |n|
      n.to_pos.merge("read" => read_ids.include?(n.id))
    end
  end
end
