Sequel.migration do
  change do
    create_table(:testimonials) do
      primary_key :id

      String :name, null: false
      # Freeform display string per lib/data/testimonials.js ("Villa Owner,
      # Sobha Royal Crest") — not a FK to Clients/Properties, same reasoning
      # as Blog#author being plain jsonb rather than a staff_id: this is a
      # byline, not necessarily tied to a real Client/Property record.
      String :role
      String :avatar
      Integer :rating, default: 5
      String :quote, text: true
      # TESTIMONIAL_STATUSES (the live admin page's approve/reject workflow):
      # Approved / Pending / Rejected — plain string with an app-level
      # allowed list, same convention as Blog#status/Lead#status rather than
      # a DB-level enum.
      String :status, default: 'Pending'

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :status
      index :name
    end
  end
end
