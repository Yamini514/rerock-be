class App::Services::Refunds < App::Services::Base
  def model; Refund; end

  # Mirrors lib/data/finance.js: search by client name, plus exact filters
  # for status/client_id/property_id.
  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    ds = ds.where(client_id: qs[:client_id]) if qs[:client_id].present?
    ds = ds.where(property_id: qs[:property_id]) if qs[:property_id].present?
    if qs[:search].present?
      term = "%#{qs[:search]}%"
      ds = ds.where(Sequel.like(:client_name, term, case_insensitive: true))
    end
    return_success(ds.all.map(&:to_pos))
  end

  # client_name/property_name default from the linked Client/Property's own
  # name when a client_id/property_id is given but the fallback string isn't
  # explicitly passed — same pattern as Deals#create/Invoices#create.
  def create
    data = data_for(:save)
    if data[:client_name].blank? && data[:client_id].present?
      client = Client[data[:client_id]]
      data[:client_name] = client.name if client
    end
    if data[:property_name].blank? && data[:property_id].present?
      property = Property[data[:property_id]]
      data[:property_name] = property.title if property
    end
    save(model.new(data))
  end

  def self.fields
    {
      save: [
        :client_id, :property_id, :client_name, :property_name,
        :amount, :reason, :status, :requested_date
      ]
    }
  end
end
