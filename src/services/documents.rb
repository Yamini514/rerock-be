# Admin CRM — Client Details > Documents tab. Reuses the same `documents`
# table/Document model as the Client Portal's own self-service upload
# (services/client_documents.rb) rather than a separate mock/table, so an
# admin sees the exact same real rows a client uploaded (and a client sees
# whatever an admin attaches). `src` here is a real S3 URL (see the
# 'client-documents' presign purpose in services/uploads.rb) since the
# admin token can reach the admin-only presign endpoint — unlike the
# client-portal path, which stays on the base64 fallback.
class App::Services::Documents < App::Services::Base
  def model; Document; end

  # Scoped to a single client via ?client_id= — the Client Details page's
  # only real use case. Falls back to unscoped (all documents) if omitted,
  # matching every other do_crud'd list.
  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(client_id: qs[:client_id]) if qs[:client_id].present?
    return_success(ds.all.map(&:to_pos))
  end

  def create
    client = Client[params[:client_id]]
    return_errors!("Client not found.", 404) if client.nil?
    return_errors!("A document name is required.", 400) if params[:name]&.strip.blank?
    return_errors!("Category is required.", 400) if params[:category].blank?
    return_errors!("No file was attached.", 400) if params[:src].blank?

    # Skips the Pending -> Verified -> Approved queue built for client
    # self-uploads (client_documents.rb) — an admin attaching a document
    # directly has no one left to verify it.
    document = Document.new(data_for(:save).merge(client_name: client.name, status: "Approved"))
    save(document) { |o| o.notify_agent_of_upload!; return_success(o.to_pos) }
  end

  def self.fields
    { save: [:client_id, :property_id, :name, :category, :src, :notes] }
  end
end
