Sequel.migration do
  change do
    create_table(:notifications) do
      primary_key :id

      # NOTIFICATION_TYPES per lib/data/notifications.js: price/visit/
      # recommendation/portfolio/document — plain string with an app-level
      # allowed list, same convention as every other status/type column
      # elsewhere (Lead#status, Blog#status, etc.), plus "broadcast" for
      # notifications created via the admin page's own broadcast form.
      String :type, null: false
      String :icon, null: false # Lucide icon name, e.g. "TrendingUp"
      String :title, null: false
      String :message, text: true, null: false
      Boolean :read, default: false

      # No separate `time` column — the mock's `time` field ("2 hours ago")
      # is a fake relative string with no real timestamp behind it.
      # `created_at` is the real timestamp; the frontend computes a
      # relative-time display from it client-side instead (see
      # lib/utils.js's timeAgo()), same "created_at replaces the mock's fake
      # relative-time string" convention as Activity Logs/Audit Logs.
      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :type
      index :read
      index :created_at
    end
  end
end
