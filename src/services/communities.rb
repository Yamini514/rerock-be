class App::Services::Communities < App::Services::Base
  def model; Community; end

  # Mirrors lib/data/communities.js: search by name, plus filters for the
  # three FKs (builder/area/location) and status, and the Active/Archived
  # scope shared by every Property Catalog resource so far.
  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(archived: qs[:archived].to_s == 'true') if qs.key?(:archived)
    ds = ds.where(builder_id: qs[:builder_id]) if qs[:builder_id].present?
    ds = ds.where(area_id: qs[:area_id]) if qs[:area_id].present?
    ds = ds.where(location_id: qs[:location_id]) if qs[:location_id].present?
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    if qs[:search].present?
      ds = ds.where(Sequel.like(:name, "%#{qs[:search]}%", case_insensitive: true))
    end

    # Opt-in: same non-breaking contract as Properties#list — no `page`
    # param means the exact bare-array response every existing caller
    # already gets.
    if qs.key?(:page)
      total = ds.count
      return_success(ds.limit(limit).offset(offset).all.map(&:to_pos), meta: { total: total, page: (qs[:page] || 1).to_i, page_size: page_size })
    else
      return_success(ds.all.map(&:to_pos))
    end
  end

  # Archive/restore (archiveCommunity/restoreCommunity in the mock) and the
  # featured toggle (toggleCommunityFeatured) are all plain flips of a column,
  # so they ride the standard PUT/update below — whitelisted like any other
  # saveable field, same pattern as every other Property Catalog resource.
  #
  # amenity_ids is a plain Postgres integer[] (see migrations/0011 and
  # ARCHITECTURE.md for why this was chosen over a community_amenities join
  # table): Base#create/#update just slice params via data_for(:save) and
  # assign them straight onto the model, so an array field flows through
  # exactly like Builder's awards/certifications text[] columns already do —
  # no custom many-to-many code needed here at all.
  def self.fields
    {
      save: [
        :slug, :name, :type, :builder_id, :area_id, :location_id, :tagline, :status,
        :featured, :trending, :homepage_visibility, :rera, :price_min, :price_max,
        :unit_types, :total_units, :available_units, :possession, :investment_score,
        :growth_pct, :last_price_update, :hero_image, :gallery, :overview, :master_plan,
        :amenity_ids, :pricing_trend, :nearby, :documents, :seo, :archived
      ]
    }
  end

  # Overrides Base#update purely to also stamp `last_price_update` and
  # record a price_histories row whenever price_min/price_max actually
  # change via the normal single-record edit path (the Pricing tab's "Edit"
  # modal) — not just the dedicated bulk-update action below. The generic
  # audit_logs trail Base#save already writes for free is untouched;
  # price_histories is additive, purpose-built for the Pricing tab's own
  # review-date/next-review/change-type needs a generic audit row can't
  # express (see migrations/0056's comment).
  def update(data = nil)
    data ||= data_for(:save)
    price_changing = (data.key?(:price_min) && data[:price_min].to_i != item.price_min) ||
                      (data.key?(:price_max) && data[:price_max].to_i != item.price_max)
    data[:last_price_update] = Date.today if price_changing
    item.set_fields(data, data.keys)
    save(item) do |o|
      record_price_history!(o, change_type: 'manual') if price_changing
      return_success(o.to_pos)
    end
  end

  # The Pricing tab's "Bulk Pricing Update" drawer — a percent or flat
  # adjustment applied to price_min/price_max across a selected set of
  # communities in one request. Wrapped in a transaction so a mid-batch
  # failure never leaves half the selection updated and half not.
  def bulk_price_update
    ids = Array(params[:community_ids]).map(&:to_i)
    return_errors!("Select at least one community.", 400) if ids.empty?

    adjustment_type = params[:adjustment_type].presence || 'percent'
    return_errors!("Invalid adjustment type.", 400) unless %w[percent flat].include?(adjustment_type)

    value = params[:value].to_f
    return_errors!("Enter a non-zero adjustment.", 400) if value.zero?

    updated = App.db.transaction do
      Community.where(id: ids).all.map do |community|
        if adjustment_type == 'percent'
          community.price_min = (community.price_min * (1 + value / 100.0)).round
          community.price_max = (community.price_max * (1 + value / 100.0)).round
        else
          community.price_min = (community.price_min + value).round
          community.price_max = (community.price_max + value).round
        end
        community.last_price_update = Date.today
        community.save
        record_price_history!(community, change_type: 'bulk', notes: params[:notes])
        community
      end
    end

    return_success(updated.map(&:to_pos))
  end

  private

  def record_price_history!(community, change_type:, notes: nil)
    PriceHistory.create(
      community_id: community.id,
      price_min: community.price_min,
      price_max: community.price_max,
      growth_pct: community.growth_pct,
      change_type: change_type,
      notes: notes,
      changed_by: audit_changed_by
    )
  rescue => e
    # Same "never let a secondary write break the real save that just
    # succeeded" contract as Base's own write_audit_log! — a broken history
    # insert must not surface as a failure of the price update itself.
    App.logger.error("[PriceHistory] write failed for Community ##{community.id}: #{e.message}")
  end
end
