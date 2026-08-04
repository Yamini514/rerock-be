Sequel.migration do
  change do
    # Finance — Refunds. Unlike Invoices/Payments/Taxes, the mock's refunds[]
    # was never derived from closed Deals (there's no "cancelled" deal stage
    # to derive from) — it was already a standalone dataset, keyed by client/
    # property name only, no dealId. Promoted here to real nullable Client/
    # Property FKs (both real, built resources) rather than plain strings,
    # same "real FK + fallback string" shape used throughout Finance/CRM,
    # since a refund is naturally tied to a specific client and property even
    # without a deal record.
    create_table(:refunds) do
      primary_key :id

      foreign_key :client_id, :clients, null: true
      foreign_key :property_id, :properties, null: true
      String :client_name, null: false
      String :property_name

      Integer :amount, default: 0
      String :reason
      # REFUND_STATUSES (lib/data/finance.js): Requested / Processed /
      # Rejected — plain string, app-level allowed list.
      String :status, default: 'Requested'
      Date :requested_date

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :client_id
      index :property_id
      index :status
    end
  end
end
