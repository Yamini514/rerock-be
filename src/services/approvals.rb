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
end
