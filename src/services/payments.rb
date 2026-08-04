class App::Services::Payments < App::Services::Base
  def model; Payment; end

  # Mirrors lib/data/finance.js: search by client name, plus exact filters
  # for deal_id/client_id/mode.
  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(deal_id: qs[:deal_id]) if qs[:deal_id].present?
    ds = ds.where(client_id: qs[:client_id]) if qs[:client_id].present?
    ds = ds.where(mode: qs[:mode]) if qs[:mode].present?
    if qs[:search].present?
      term = "%#{qs[:search]}%"
      ds = ds.where(Sequel.like(:client_name, term, case_insensitive: true))
    end
    return_success(ds.all.map(&:to_pos))
  end

  # client_name defaults from the linked Deal/Client's own name, same pattern
  # as Invoices#create.
  def create
    data = data_for(:save)
    if data[:client_name].blank? && data[:deal_id].present?
      deal = Deal[data[:deal_id]]
      data[:client_name] = deal.client_name if deal
    end
    if data[:client_name].blank? && data[:client_id].present?
      client = Client[data[:client_id]]
      data[:client_name] = client.name if client
    end
    save(model.new(data))
  end

  def self.fields
    {
      save: [
        :deal_id, :client_id, :client_name, :milestone, :amount, :mode, :paid_date
      ]
    }
  end
end
