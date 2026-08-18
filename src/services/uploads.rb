# Real S3 upload flow — replaces every base64 data: URL "upload" (property
# images/floor plans/documents, community gallery/documents, builder logos,
# media library, client/lead documents, avatars) with actual object storage.
# One shared presigned-PUT service rather than a near-duplicate per module:
# every target column (Property#images, Community#gallery, Builder#logo,
# MediaItem#src, Document#src, ...) is just a plain string regardless of
# which model eventually stores it, so the upload mechanism itself doesn't
# need to know or care which one.
#
# Flow: frontend calls POST .../uploads/presign with
# {filename, content_type, purpose} -> gets back {id, key, upload_url,
# public_url, expires_in} -> PUTs the raw file bytes directly to
# `upload_url` (S3, not through this backend) -> saves `public_url` into
# the normal existing form field via the entity's own save/update, exactly
# like it already saves a base64 string today. `id` is the new `uploads`
# table row's real primary key — callers embed it as that image/document's
# own `id` (instead of a random client-generated one) so it can be looked
# up later via GET .../uploads/:id. Old base64 rows are untouched and keep
# rendering unchanged — an <img>/<a> doesn't care whether its src is a
# data: URI or an https:// URL, so there's no backfill/migration needed for
# this to be fully backward compatible.
#
# `public_url` points at this app's own #file action (GET
# .../uploads/:uuid/file), not the bucket directly — the bucket stays fully
# private (no public-read policy needed at all) and #file fetches the
# object server-side via Aws::S3::Client using the same credentials the
# presigner already uses. It's keyed by `uuid` rather than the row's
# sequential `id` specifically so this can stay reachable with no auth at
# all (needed for the public site to render property/community images)
# without making every upload trivially enumerable by looping id=1,2,3,...
# — see migrations/0096's own comment on the `uuid` column.
#
# Mounted three times (backend/src/routes.rb): unrestricted under the Admin
# Portal, and scoped via `allowed_purposes:` under the Client/Agent/RAM
# Portals' own `me` blocks — each of those non-admin JWTs can only ever
# presign the one purpose that portal is allowed to use, enforced
# server-side (never trust the frontend to only ever send the "right" one).
class App::Services::Uploads < App::Services::Base
  # Never trust a client-supplied key/prefix directly (path traversal /
  # arbitrary-key overwrite risk) — only this closed, server-side enum, each
  # mapped to a fixed S3 key prefix.
  PURPOSE_PREFIXES = {
    'property-images' => 'properties/images',
    'property-floor-plans' => 'properties/floor-plans',
    'property-documents' => 'properties/documents',
    'community-gallery' => 'communities/gallery',
    'community-documents' => 'communities/documents',
    'community-master-plan' => 'communities/master-plan',
    'community-floor-plans' => 'communities/floor-plans',
    'builder-logo' => 'builders/logos',
    'builder-documents' => 'builders/documents',
    'collection-cover' => 'collections/covers',
    'media-library' => 'media-library',
    'area-image' => 'areas/images',
    # Admin (CRM) attaching a document to a client's record — a different
    # feature from the Client Portal's own self-service upload
    # (services/client_documents.rb), which now gets its own scoped presign
    # under 'client-portal/me/uploads' (routes.rb) using this same purpose.
    'client-documents' => 'clients/documents',
    # Admin's Agent Detail > Documents tab (HR-style docs — Aadhaar, PAN,
    # employment agreement, etc., see migrations/0019's own comment on that
    # jsonb column).
    'agent-documents' => 'agents/documents',
    # Agent Portal's own lead-documents tab (components/agent/leads/tabs/
    # DocumentsTab.js) — distinct from 'agent-documents' above, which is the
    # agent's own HR paperwork, not a document shared with one of their leads.
    'lead-documents' => 'leads/documents',
    'user-avatar' => 'users/avatars',
    'ram-avatar' => 'ram-members/avatars',
  }.freeze

  MAX_FILENAME_LENGTH = 200
  URL_EXPIRES_IN = 300 # 5 minutes — plenty for a browser to start the PUT

  def model; Upload; end

  def presign(allowed_purposes: PURPOSE_PREFIXES.keys)
    return_errors!("Invalid upload purpose.", 400) unless allowed_purposes.include?(params[:purpose])
    prefix = PURPOSE_PREFIXES[params[:purpose]]

    filename = params[:filename]&.strip
    return_errors!("A filename is required.", 400) if filename.blank?

    content_type = params[:content_type].presence || 'application/octet-stream'
    # Random UUID prefix prevents overwrite/enumeration of another upload's
    # key; the original filename is kept (sanitized) purely for readability
    # in the bucket, not for uniqueness.
    sanitized_name = filename.gsub(/[^a-zA-Z0-9_.-]/, '_').slice(0, MAX_FILENAME_LENGTH)
    key = "#{prefix}/#{SecureRandom.uuid}-#{sanitized_name}"

    bucket = ENV['AWS_BUCKET']
    region = ENV['AWS_REGION'] || 'ap-south-1'
    uuid = SecureRandom.uuid

    presigner = Aws::S3::Presigner.new
    upload_url = presigner.presigned_url(:put_object, bucket: bucket, key: key, content_type: content_type, expires_in: URL_EXPIRES_IN)
    bucket_url = "https://#{bucket}.s3.#{region}.amazonaws.com/#{key}"
    public_url = "#{request.base_url}/api/uploads/#{uuid}/file"

    upload = Upload.create(
      uuid: uuid, key: key, bucket: bucket, url: bucket_url, purpose: params[:purpose],
      filename: sanitized_name, content_type: content_type,
      uploaded_by: audit_changed_by, uploader_type: uploader_type
    )

    return_success(id: upload.id, key: key, upload_url: upload_url, public_url: public_url, expires_in: URL_EXPIRES_IN)
  rescue Aws::Errors::MissingRegionError, Aws::Sigv4::Errors::MissingCredentialsError => e
    App.logger.error("[Uploads] S3 presign failed: #{e.message}")
    return_errors!("Upload service is not configured.", 500)
  end

  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(purpose: params[:purpose]) if params[:purpose].present?
    return_success(ds.all.map(&:to_pos))
  end

  # Public (no auth) — see routes.rb's top-level 'uploads/:uuid/file' route
  # and this file's own header comment on why `uuid`, not `id`, is the key.
  # Streams the object straight through from S3 using our own credentials,
  # so the bucket itself never needs a public-read policy.
  def file
    upload = model.first(uuid: rp[:uuid])
    return_errors!("File not found.", 404) if upload.nil?

    object = Aws::S3::Client.new.get_object(bucket: upload.bucket, key: upload.key)
    request.response['Content-Type'] = upload.content_type.presence || 'application/octet-stream'
    request.response['Cache-Control'] = 'public, max-age=31536000, immutable'
    object.body.read
  rescue Aws::S3::Errors::NoSuchKey
    return_errors!("File not found.", 404)
  end

  private

  # Same fallback chain as Base#audit_changed_by, but returning which
  # identity kind matched (audit_changed_by only returns the display name),
  # so `uploads.uploader_type` can distinguish "admin" from "client" etc.
  def uploader_type
    return 'admin' if App.cu.user_obj
    return 'ram' if App::Helpers::CurrentRam.ram_obj
    return 'agent' if App::Helpers::CurrentAgent.agent_obj
    return 'client' if App::Helpers::CurrentClient.client_obj
    'system'
  end
end
