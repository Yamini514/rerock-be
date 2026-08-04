Sequel.migration do
  change do
    create_table(:blogs) do
      primary_key :id
      String :slug, null: false
      String :title, null: false
      String :excerpt, text: true
      String :image
      # Freeform string per lib/data/blogs.js (category is not enum-constrained
      # in the mock — "Market Insight"/"Investment Strategy"/"Buyer's Guide"
      # are just the sample values, not a fixed app-level list like
      # PropertyType#colour or Lead#status), so this stays a plain column with
      # no allowed-list validation, same reasoning as Community#type.
      String :category
      Date :date
      # readTime in the mock is a free-text string ("6 min read"), not a
      # number of minutes — kept as-is rather than splitting into an integer
      # + unit, matching the mock's own shape exactly.
      String :read_time
      # Embedded {name, role, avatar} — deliberately jsonb, not a `staff_id`
      # FK: per the task, this is freeform author metadata (a byline), not
      # necessarily a real staff/agent record, so there's nothing to point a
      # foreign key at.
      column :author, :jsonb, default: '{"name":"","role":"","avatar":""}'
      # Array of paragraph strings — lean text[] (not jsonb) since each entry
      # is a plain string with no further structure, same precedent as
      # Builder#awards/#certifications.
      column :content, 'text[]', default: '{}'
      # Not present on lib/data/blogs.js's own sample records, but the
      # existing (mock-era) admin page already treats Draft/Published as a
      # real, persisted concept (a status Badge + filter) — kept as a real
      # column so that UI keeps working as-is rather than losing behavior on
      # rewire, same judgment call as Properties' extra non-mock columns.
      String :status, default: 'Published'

      Integer :created_by
      Integer :updated_by
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :slug, unique: true
      index :category
      index :status
    end
  end
end
