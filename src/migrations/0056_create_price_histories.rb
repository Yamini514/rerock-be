Sequel.migration do
  change do
    # One immutable row per Community price change (manual single-edit or
    # bulk) — additive alongside the generic `audit_logs` table (migrations/
    # 0036), which already captures every price_min/price_max column change
    # for free via App::Services::Base#save. audit_logs rows are prose
    # strings ("Price Min: 8500000 -> 9000000"), which is exactly why the
    # admin dashboard's "Recent Pricing Updates" widget has to regex-parse
    # them — this table gives the Pricing tab (and, eventually, that same
    # widget) real structured columns instead, plus reviewer/change-type/
    # notes semantics a generic audit row can't express.
    create_table(:price_histories) do
      primary_key :id
      foreign_key :community_id, :communities, null: false

      Integer :price_min, default: 0
      Integer :price_max, default: 0
      Float :growth_pct

      # "manual" (single-record edit) vs "bulk" (Bulk Pricing Update drawer)
      # — plain string, app-level allowed list, same convention as every
      # other status/category column in this codebase.
      String :change_type, default: 'manual'
      String :notes, text: true
      String :changed_by

      DateTime :effective_date, default: Sequel::CURRENT_TIMESTAMP
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP

      index :community_id
      index :effective_date
      index [:community_id, :effective_date]
    end
  end
end
