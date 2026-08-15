# Narrow, read-only public projection of the price_histories ledger (see
# services/price_histories.rb, the full admin version) — feeds the "Pricing
# History" chart on the public Community Details page. Never exposes
# `notes`/`changed_by`/`id`/`change_type`, only what the chart needs, and
# always requires `community_id` (never a bare dump of every community's
# pricing history at once).
class App::Services::PublicPriceHistories < App::Services::Base
  def model; PriceHistory; end

  def list
    return_errors!("community_id is required.", 400) if qs[:community_id].blank?

    rows = model.where(community_id: qs[:community_id]).order(:year, :effective_date).all
    return_success(rows.map { |r| { 'year' => r.year, 'price_min' => r.price_min, 'price_max' => r.price_max, 'effective_date' => r.effective_date } })
  end
end
