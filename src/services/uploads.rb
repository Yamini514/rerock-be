# Real S3 upload flow — replaces every base64 data: URL "upload" (property
# images/floor plans/documents, community gallery/documents, builder logos,
# media library, client documents) with actual object storage. One shared
# presigned-PUT service rather than a near-duplicate per module: every
# target column (Property#images, Community#gallery, Builder#logo,
# MediaItem#src, Document#src, ...) is just a plain string regardless of
# which model eventually stores it, so the upload mechanism itself doesn't
# need to know or care which one.
#
# Flow: frontend calls POST /api/admin/uploads/presign with
# {filename, content_type, purpose} -> gets back {key, upload_url,
# public_url, expires_in} -> PUTs the raw file bytes directly to
# `upload_url` (S3, not through this backend) -> saves `public_url` into
# the normal existing form field via the entity's own save/update, exactly
# like it already saves a base64 string today. Old base64 rows are
# untouched and keep rendering unchanged — an <img>/<a> doesn't care
# whether its src is a data: URI or an https:// URL, so there's no
# backfill/migration needed for this to be fully backward compatible.
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
    'builder-logo' => 'builders/logos',
    'builder-documents' => 'builders/documents',
    'collection-cover' => 'collections/covers',
    'media-library' => 'media-library',
    # Admin (CRM) attaching a document to a client's record — a different
    # feature from the Client Portal's own self-service upload
    # (services/client_documents.rb), which stays on the base64 fallback
    # since it authenticates with a client token, not an admin one, and
    # can't reach this admin-only presign endpoint.
    'client-documents' => 'clients/documents',
  }.freeze

  MAX_FILENAME_LENGTH = 200
  URL_EXPIRES_IN = 300 # 5 minutes — plenty for a browser to start the PUT

  def presign
    prefix = PURPOSE_PREFIXES[params[:purpose]]
    return_errors!("Invalid upload purpose.", 400) if prefix.nil?

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

    presigner = Aws::S3::Presigner.new
    upload_url = presigner.presigned_url(:put_object, bucket: bucket, key: key, content_type: content_type, expires_in: URL_EXPIRES_IN)
    public_url = "https://#{bucket}.s3.#{region}.amazonaws.com/#{key}"

    return_success(key: key, upload_url: upload_url, public_url: public_url, expires_in: URL_EXPIRES_IN)
  rescue Aws::Errors::MissingRegionError, Aws::Sigv4::Errors::MissingCredentialsError => e
    App.logger.error("[Uploads] S3 presign failed: #{e.message}")
    return_errors!("Upload service is not configured.", 500)
  end
end
