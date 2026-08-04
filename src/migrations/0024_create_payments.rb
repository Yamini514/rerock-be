Sequel.migration do
  change do
    # Finance — Payments. Same reasoning as Invoices (migrations/0023): the
    # mock derived a booking-advance + final-payment installment per closed
    # Deal (getPayments()); this becomes its own real, independently-
    # persisted ledger table with real nullable Deal/Client FKs rather than a
    # value recomputed from Deals on every page load.
    create_table(:payments) do
      primary_key :id

      foreign_key :deal_id, :deals, null: true
      foreign_key :client_id, :clients, null: true
      String :client_name, null: false

      # "Booking Advance" / "Final Payment" in the mock — plain string, no
      # fixed enum enforced at the DB level (a real ledger may need more
      # milestones over time than the mock's two), same convention as
      # Expense#category.
      String :milestone
      Integer :amount, default: 0
      # PAYMENT_MODES (lib/data/finance.js): Bank Transfer / UPI / Cheque /
      # Net Banking — plain string, app-level allowed list.
      String :mode
      Date :paid_date

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :deal_id
      index :client_id
    end
  end
end
