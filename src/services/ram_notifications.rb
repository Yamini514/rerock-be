# RAM Portal's own read-only view over admin-broadcast notifications targeted
# at audience "ram" — same shape as services/client_notifications.rb, kept
# as its own copy rather than a shared concern since RamMember/Client/Agent
# are three separate identity tables with no shared row to key off of (same
# reasoning as ram_member.rb's own comment on why it copies rather than
# shares with User).
class App::Services::RamNotifications < App::Services::Base
  def model; Notification; end

  def mine
    ram = CurrentRam.ram_obj
    return_errors!("Not signed in.", 401) if ram.nil?

    return_success(notifications_with_read_state(ram.id))
  end

  # Toggles read/unread (matches components/portal/NotificationItem's
  # "Mark read"/"Mark unread" button, which always flips current state)
  # rather than only ever marking read.
  def mark_read
    ram = CurrentRam.ram_obj
    return_errors!("Not signed in.", 401) if ram.nil?

    notification = visible_scope(ram.id).where(id: rp[:id]).first
    return_errors!("Notification not found.", 404) if notification.nil?

    existing = NotificationRead.where(notification_id: notification.id, recipient_type: "ram", recipient_id: ram.id).first
    existing ? existing.delete : NotificationRead.create(notification_id: notification.id, recipient_type: "ram", recipient_id: ram.id)
    return_success(notifications_with_read_state(ram.id))
  end

  def mark_all_read
    ram = CurrentRam.ram_obj
    return_errors!("Not signed in.", 401) if ram.nil?

    ids = visible_scope(ram.id).select_map(:id)
    already_read = NotificationRead.where(recipient_type: "ram", recipient_id: ram.id, notification_id: ids).select_map(:notification_id)
    (ids - already_read).each { |nid| NotificationRead.create(notification_id: nid, recipient_type: "ram", recipient_id: ram.id) }

    return_success(notifications_with_read_state(ram.id))
  end

  private

  # Broadcasts (recipient_id nil) plus anything targeted at this one RAM
  # member specifically — never another RAM member's personal notification.
  def visible_scope(ram_id)
    Notification.where(audience: "ram").where(Sequel.|({ recipient_id: nil }, { recipient_id: ram_id }))
  end

  def notifications_with_read_state(ram_id)
    read_ids = NotificationRead.where(recipient_type: "ram", recipient_id: ram_id).select_map(:notification_id)
    visible_scope(ram_id).order(Sequel.desc(:created_at), Sequel.desc(:id)).all.map do |n|
      n.to_pos.merge("read" => read_ids.include?(n.id))
    end
  end
end
