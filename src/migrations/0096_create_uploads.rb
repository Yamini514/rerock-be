Sequel.migration do
  change do
    create_table(:uploads) do
      primary_key :id

      # Unguessable, unlike `id` — used as the lookup key for the public
      # file-serving route (GET .../uploads/:uuid/file, see
      # services/uploads.rb#file) so that route can stay reachable with no
      # auth at all (needed for the public site to render property/
      # community images) without making every upload trivially enumerable
      # by looping id=1,2,3,.... `id` stays the admin-only, authenticated
      # GET .../uploads/:id lookup's key.
      String :uuid, null: false

      String :key, null: false        # full S3 object key
      String :bucket, null: false
      String :url, null: false        # public S3 URL (kept for reference; #file is what actually serves it)
      String :purpose, null: false    # one of Uploads::PURPOSE_PREFIXES' keys
      String :filename, null: false
      String :content_type

      # Stays nil — the browser PUTs the file straight to S3 (see
      # services/uploads.rb's presign flow), so the backend never actually
      # sees the file's bytes to measure them.
      Integer :size_bytes

      # Same deferred-identity convention as models/media_item.rb#uploaded_by
      # — a plain display-name string, not a real FK, since the uploader may
      # be an admin User, a Client, an Agent, or a RAM member (four separate,
      # non-unifiable id spaces/tables).
      String :uploaded_by
      String :uploader_type

      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :uuid, unique: true
      index :purpose
      index :key, unique: true
      index :created_at
    end
  end
end
