class App::Services::Approvals < App::Services::Base
  def model; Approval; end

  # Newest-first, plus exact status/type filters for the Dashboard widget's
  # (currently implicit, Pending-only) view and any future filtered list.
  def list
    ds = model.order(Sequel.desc(:created_at), Sequel.desc(:id))
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    ds = ds.where(type: qs[:type]) if qs[:type].present?
    return_success(ds.all.map(&:to_pos))
  end

  # No archive/restore concept (same as Testimonials/Blogs/Leads) —
  # approve/reject are just a `status` transition and ride the standard
  # PUT/update below, `status` whitelisted like any other saveable field.
  def self.fields
    {
      save: [
        :type, :title, :requested_by, :status, :entity, :entity_id, :notes
      ]
    }
  end

  # Same as Base#update, but when this approval is for a Document (created
  # by services/agent_portal.rb#verify_my_document), an admin's approve/
  # reject here is the actual source of truth for that document's own
  # status — and, on approval, the trigger for notifying the client. This
  # lets Document Verification reuse the existing PendingApprovalsWidget
  # entirely instead of a dedicated admin page.
  def update(data=nil)
    data ||= data_for(:save)
    item.set_fields(data, data.keys)
    save(item) do |obj|
      sync_document_status!(obj) if obj.entity == "Document"
      return_success(obj.to_pos)
    end
  end

  private

  def sync_document_status!(approval)
    return unless %w[Approved Rejected].include?(approval.status)

    document = Document[approval.entity_id.to_i]
    return if document.nil?

    allowed = { status: approval.status, approved_by_user_id: CurrentUser.id, approved_at: Time.now }
    document.set_fields(allowed, allowed.keys)
    document.save

    if approval.status == "Approved"
      Notification.create(
        audience: "client",
        recipient_id: document.client_id,
        type: "document",
        icon: "FileCheck2",
        title: "Document approved",
        message: "Your #{document.category.downcase} \"#{document.name}\" has been verified and approved."
      )
    end
  end
end
