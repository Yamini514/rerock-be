# Client Portal document upload — replaces DocumentsClient.js's old
# local-only mock (nothing was ever sent to the backend). Follows the same
# no-real-file-storage convention already established by MediaItem#src
# (migrations/0038): `src` is a plain string (a base64 data: URL from
# DocumentUploader.js), not a real uploaded file.
class App::Services::ClientDocuments < App::Services::Base
  def model; Document; end

  def create
    client = CurrentClient.client_obj
    return_errors!("Not signed in.", 401) if client.nil?

    name = params[:name]&.strip
    category = params[:category]
    src = params[:src]

    return_errors!("A document name is required.", 400) if name.blank?
    return_errors!("Category is required.", 400) if category.blank?
    return_errors!("No file was attached.", 400) if src.blank?

    property = params[:property_slug].present? ? Property.first(slug: params[:property_slug]) : nil

    document = Document.new(
      client_id: client.id,
      property_id: property&.id,
      client_name: client.name,
      name: name,
      category: category,
      src: src,
      notes: params[:notes],
      status: "Pending"
    )
    save(document) { |o| o.notify_agent_of_upload!; return_success(o.to_pos) }
  end

  # The client's own uploaded documents, any status.
  def mine
    client = CurrentClient.client_obj
    return_errors!("Not signed in.", 401) if client.nil?

    return_success(Document.where(client_id: client.id).order(Sequel.desc(:created_at)).all.map(&:to_pos))
  end
end
