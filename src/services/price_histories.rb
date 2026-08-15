# Feed of Community price changes. Most rows are written exclusively from
# services/communities.rb's #update (single edit) and #bulk_price_update
# (bulk edit) as an immutable audit trail — this service's #create/#update/
# #delete below are for the ADMIN Pricing tab's own "Price History" ledger
# management, and are deliberately restricted to only ever touch rows this
# same service created (change_type: 'manual-entry'), so the real 'manual'/
# 'bulk' audit rows stay exactly as immutable as they've always been.
class App::Services::PriceHistories < App::Services::Base
  def model; PriceHistory; end

  def self.fields
    { save: [:community_id, :year, :price_min, :price_max, :notes] }
  end

  def list
    ds = model.order(Sequel.desc(:year), Sequel.desc(:effective_date))
    ds = ds.where(community_id: qs[:community_id]) if qs[:community_id].present?

    if qs.key?(:page)
      total = ds.count
      return_success(ds.limit(limit).offset(offset).all.map(&:to_pos), meta: { total: total, page: (qs[:page] || 1).to_i, page_size: page_size })
    else
      return_success(ds.all.map(&:to_pos))
    end
  end

  # Admin-entered historical ledger row (e.g. backfilling "2023") — distinct
  # from the auto-logged 'manual'/'bulk' rows above, so it's always stamped
  # 'manual-entry' server-side regardless of what a client sends.
  def create
    data = data_for(:save)
    data[:change_type] = 'manual-entry'
    data[:effective_date] ||= Time.now
    save(model.new(data))
  end

  def update(data = nil)
    return_errors!("Cannot edit an automatically recorded price change.", 403) unless item.change_type == 'manual-entry'
    super
  end

  def delete
    return_errors!("Cannot delete an automatically recorded price change.", 403) unless item.change_type == 'manual-entry'
    super
  end
end
