class App::Services::MediaItems < App::Services::Base
  def model; MediaItem; end

  # Mirrors lib/data/media.js: newest-first, search by name OR tags, and an
  # exact uploaded_by filter (matching the admin page's own "uploaded by"
  # dropdown, same convention as Notifications' type filter).
  def list
    ds = model.order(Sequel.desc(:created_at), Sequel.desc(:id))
    ds = ds.where(uploaded_by: qs[:uploaded_by]) if qs[:uploaded_by].present?
    if qs[:search].present?
      # Same `Dataset#or` pitfall documented in leads.rb/notifications.rb:
      # `Dataset#or` ORs the new condition against the dataset's *entire*
      # existing WHERE clause, which would silently drop the uploaded_by
      # filter above whenever a search term is also present. Combine the
      # OR conditions with `|` first, then AND the whole thing in.
      # Tags is a text[] column — rather than reach for pg_array's ANY/
      # overlap operators (more moving parts for a simple substring search),
      # flatten it to a space-joined string and ILIKE that, same "keep it
      # simple" judgment call as everywhere else arrays show up read-only.
      term = "%#{qs[:search]}%"
      ds = ds.where(
        Sequel.like(:name, term, case_insensitive: true) |
        Sequel.like(Sequel.function(:array_to_string, :tags, ' '), term, case_insensitive: true)
      )
    end
    return_success(ds.all.map(&:to_pos))
  end

  # No archive/restore concept — delete is a real hard delete, matching
  # Notifications' plain delete (this is metadata for a simulated upload,
  # not a system log). Every field rides the standard PUT/update.
  def self.fields
    {
      save: [
        :src, :name, :tags, :uploaded_by
      ]
    }
  end
end
