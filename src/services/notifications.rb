class App::Services::Notifications < App::Services::Base
  def model; Notification; end

  # Mirrors lib/data/notifications.js: newest-first, an exact `type` filter
  # (price/visit/recommendation/portfolio/document/broadcast — matches the
  # admin page's own tab-per-type UI) and a `read`/`unread` filter, plus
  # search across title/message.
  def list
    ds = model.order(Sequel.desc(:created_at), Sequel.desc(:id))
    ds = ds.where(type: qs[:type]) if qs[:type].present?
    ds = ds.where(read: qs[:read] == 'true') if qs[:read].present?
    if qs[:search].present?
      # Same `Dataset#or` pitfall documented in leads.rb/activity_logs.rb:
      # `Dataset#or` ORs the new condition against the dataset's *entire*
      # existing WHERE clause, which would silently drop the type/read
      # filters above whenever a search term is also present. Combine the
      # OR conditions with `|` first, then AND the whole thing in.
      term = "%#{qs[:search]}%"
      ds = ds.where(
        Sequel.like(:title, term, case_insensitive: true) |
        Sequel.like(:message, term, case_insensitive: true)
      )
    end
    return_success(ds.all.map(&:to_pos))
  end

  # Custom action backing the admin page's "Mark all as read" button — not
  # part of do_crud's CRUDL set, wired as its own r.post in routes.rb. Flips
  # every currently-unread row in one statement rather than the frontend
  # firing one PUT per row (same "one real write, not N" reasoning as
  # Collections' virtual-featured-properties note in ARCHITECTURE.md).
  def mark_all_read
    model.where(read: false).update(read: true, updated_at: Sequel::CURRENT_TIMESTAMP)
    return_success(model.order(Sequel.desc(:created_at), Sequel.desc(:id)).all.map(&:to_pos))
  end

  # No archive/restore concept — delete is a real hard delete (matching
  # Leads' plain `deleteLead`), and read/unread is just a `read` transition
  # that rides the standard PUT/update, whitelisted like any other field.
  def self.fields
    {
      save: [
        :type, :icon, :title, :message, :read, :audience
      ]
    }
  end
end
