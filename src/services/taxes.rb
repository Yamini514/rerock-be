class App::Services::Taxes < App::Services::Base
  def model; Tax; end

  # Mirrors lib/data/finance.js: exact filters for deal_id/type/status (no
  # free-text search field — the mock's own rows have no name-shaped column
  # to search by, just a deal_id and a type; Table's own client-side search
  # box already covers the "search by tax ID or deal id" placeholder on the
  # frontend, same as every other Finance list page).
  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(deal_id: qs[:deal_id]) if qs[:deal_id].present?
    ds = ds.where(type: qs[:type]) if qs[:type].present?
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    return_success(ds.all.map(&:to_pos))
  end

  def self.fields
    {
      save: [:deal_id, :type, :amount, :period, :status]
    }
  end
end
