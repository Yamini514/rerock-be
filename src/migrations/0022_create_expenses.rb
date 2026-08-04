Sequel.migration do
  change do
    # Finance — Expenses. Matches lib/data/finance.js's expenses[] field
    # catalog: a standalone operating-cost ledger with no upstream mock
    # source table (unlike Invoices/Payments/Taxes, which the mock derived
    # from closed Deals) — now a real, independently-persisted table, per the
    # roadmap's Finance phase (Commission/Revenue stay computed reports over
    # Agents/Deals, see services/reports.rb; no migration for those two).
    create_table(:expenses) do
      primary_key :id

      # EXPENSE_CATEGORIES (lib/data/finance.js: Marketing, Staff Salaries,
      # Office Rent, Legal & Compliance, Technology, Sales Commission Payout)
      # stays a frontend-only fixed list — plain string column with an
      # app-level allowed list, same convention as every other enum-shaped
      # field in this codebase (Lead#status, Deal#stage, Community#type...).
      String :category, null: false
      String :description
      Integer :amount, default: 0

      # Plain display string ("Jul 2026"), matching the mock's own `month`
      # field exactly rather than decomposing into a real Date — the mock
      # never stored a day-of-month, and the UI only ever renders/sorts/
      # groups by this label, not a real date range.
      String :month
      String :approved_by

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :category
    end
  end
end
