# Read-only feed of Community price changes — rows are written exclusively
# from services/communities.rb's #update (single edit) and #bulk_price_update
# (bulk edit), never created/edited/deleted directly through this service.
class App::Services::PriceHistories < App::Services::Base
  def model; PriceHistory; end

  def list
    ds = model.order(Sequel.desc(:effective_date))
    ds = ds.where(community_id: qs[:community_id]) if qs[:community_id].present?

    if qs.key?(:page)
      total = ds.count
      return_success(ds.limit(limit).offset(offset).all.map(&:to_pos), meta: { total: total, page: (qs[:page] || 1).to_i, page_size: page_size })
    else
      return_success(ds.all.map(&:to_pos))
    end
  end
end
