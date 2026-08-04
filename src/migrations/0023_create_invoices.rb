Sequel.migration do
  change do
    # Finance — Invoices. The mock derived one invoice per closed Deal
    # (lib/data/finance.js's getInvoices()); now that Deals AND Clients are
    # both real, built resources, this becomes a real, independently-
    # persisted table with real FKs instead of a value recomputed from Deals
    # on every page load — an invoice is a transactional record in its own
    # right (it can be edited/paid/re-issued independently of the deal it
    # originated from).
    create_table(:invoices) do
      primary_key :id

      # Both nullable: an invoice can be raised before a deal/client is
      # formally linked (or for a deal/client that predates this table), same
      # "real FK + fallback string" reasoning as Deal#client_id/#client_name
      # and Deal#property_id/#property_name (migrations/0018).
      foreign_key :deal_id, :deals, null: true
      foreign_key :client_id, :clients, null: true
      String :client_name, null: false
      String :property_name

      # Agent Network is real now, but Deal#agent_slug (the source this was
      # ever cross-referenced from) is still a deferred plain string, not a
      # real FK — so this stays a plain nullable string too, copied from the
      # linked Deal's own agent_slug at create time (see services/invoices.rb).
      String :agent_slug

      Integer :amount, default: 0
      # INVOICE_STATUSES (lib/data/finance.js): Paid / Partially Paid / Unpaid
      # — plain string, app-level allowed list, same convention as elsewhere.
      String :status, default: 'Unpaid'
      Date :issued_date
      Date :due_date

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :deal_id
      index :client_id
      index :status
    end
  end
end
