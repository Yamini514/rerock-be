# Client Portal's own read-only view over admin-broadcast notifications
# targeted at audience "client" — deliberately separate from
# App::Services::Notifications (the Admin Portal's own global feed over the
# same `notifications` table). Read state is tracked per-recipient via the
# `notification_reads` join table (row existence = read) rather than a
# shared `read` column, so one client marking a broadcast read never affects
# any other client's unread count.
class App::Services::ClientNotifications < App::Services::Base
  def model; Notification; end

  def mine
    client = CurrentClient.client_obj
    return_errors!("Not signed in.", 401) if client.nil?

    return_success(notifications_with_read_state(client.id))
  end

  # Toggles read/unread (matches components/portal/NotificationItem's
  # "Mark read"/"Mark unread" button, which always flips current state)
  # rather than only ever marking read.
  def mark_read
    client = CurrentClient.client_obj
    return_errors!("Not signed in.", 401) if client.nil?

    notification = visible_scope(client.id).where(id: rp[:id]).first
    return_errors!("Notification not found.", 404) if notification.nil?

    existing = NotificationRead.where(notification_id: notification.id, recipient_type: "client", recipient_id: client.id).first
    existing ? existing.delete : NotificationRead.create(notification_id: notification.id, recipient_type: "client", recipient_id: client.id)
    return_success(notifications_with_read_state(client.id))
  end

  def mark_all_read
    client = CurrentClient.client_obj
    return_errors!("Not signed in.", 401) if client.nil?

    ids = visible_scope(client.id).select_map(:id)
    already_read = NotificationRead.where(recipient_type: "client", recipient_id: client.id, notification_id: ids).select_map(:notification_id)
    (ids - already_read).each { |nid| NotificationRead.create(notification_id: nid, recipient_type: "client", recipient_id: client.id) }

    return_success(notifications_with_read_state(client.id))
  end

  private

  # Broadcasts (recipient_id nil) plus anything targeted at this one client
  # specifically (e.g. "your site visit is scheduled") — never another
  # client's personal notification.
  def visible_scope(client_id)
    Notification.where(audience: "client").where(Sequel.|({ recipient_id: nil }, { recipient_id: client_id }))
  end

  def notifications_with_read_state(client_id)
    read_ids = NotificationRead.where(recipient_type: "client", recipient_id: client_id).select_map(:notification_id)
    visible_scope(client_id).order(Sequel.desc(:created_at), Sequel.desc(:id)).all.map do |n|
      n.to_pos.merge("read" => read_ids.include?(n.id))
    end
  end
end
