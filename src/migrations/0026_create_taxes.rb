Sequel.migration do
  change do
    # Finance — Taxes (GST + Stamp Duty filings). Same reasoning as Invoices/
    # Payments (migrations/0023/0024): the mock derived two tax records (GST,
    # Stamp Duty) per closed Deal (getTaxRecords()); this becomes its own
    # real, independently-persisted filing table with a real nullable Deal
    # FK. Table/model named `Tax`/`taxes` (no reserved-word collision in
    # Postgres or in this app's routes.rb — checked before adding; the
    # `type` column below is also safe: Sequel only treats a `type` column
    # specially when the `single_table_inheritance` plugin is loaded, which
    # this app's setup_sequel! never does, and Community#type already
    # proves a plain `type` string column works fine here).
    create_table(:taxes) do
      primary_key :id

      foreign_key :deal_id, :deals, null: true

      # TAX_TYPES (lib/data/finance.js): GST / Stamp Duty — plain string,
      # app-level allowed list, same convention as Expense#category.
      String :type, null: false
      Integer :amount, default: 0
      # Plain display string ("Jul 2026"), same reasoning as Expense#month.
      String :period
      # TAX_STATUSES: Filed / Pending / Overdue.
      String :status, default: 'Pending'

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :deal_id
      index :type
      index :status
    end
  end
end
