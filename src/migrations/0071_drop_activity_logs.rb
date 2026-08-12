Sequel.migration do
  change do
    # Activity Logs was wired end-to-end (table/model/service/route/page) but
    # nothing in the backend ever wrote a row to it (see services/base.rb's
    # audit-log hook, which only covers Audit Logs) — removed as dead weight.
    drop_table(:activity_logs)
  end
end
