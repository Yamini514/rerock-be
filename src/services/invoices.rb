class App::Services::Invoices < App::Services::Base
  def model; Invoice; end

  # Mirrors lib/data/finance.js: search by client name, plus exact filters
  # for status/deal_id/client_id.
  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    ds = ds.where(deal_id: qs[:deal_id]) if qs[:deal_id].present?
    ds = ds.where(client_id: qs[:client_id]) if qs[:client_id].present?
    if qs[:search].present?
      # Single search field (client_name) — no `|` combination needed, same
      # as SiteVisits#list; a plain `where` chained onto the existing dataset
      # keeps the status/deal_id/client_id filters above intact.
      term = "%#{qs[:search]}%"
      ds = ds.where(Sequel.like(:client_name, term, case_insensitive: true))
    end
    return_success(ds.all.map(&:to_pos))
  end

  # client_name/property_name/agent_slug default from the linked Deal's own
  # denormalized fields when a deal_id is given but the fallback strings
  # aren't explicitly passed (a Deal already carries its own client_name/
  # property_name/agent_slug — see services/deals.rb); client_name falls
  # further back to the linked Client's own name when only client_id is
  # given. Same "derive the denormalized string from the real FK's own
  # record" pattern as Deals#create.
  def create
    data = data_for(:save)
    if data[:deal_id].present?
      deal = Deal[data[:deal_id]]
      if deal
        data[:client_name] = deal.client_name if data[:client_name].blank?
        data[:property_name] = deal.property_name if data[:property_name].blank?
        data[:agent_slug] = deal.agent_slug if data[:agent_slug].blank?
      end
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
        :deal_id, :client_id, :client_name, :property_name, :agent_slug,
        :amount, :status, :issued_date, :due_date
      ]
    }
  end
end
