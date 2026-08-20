class App::Services::Communities < App::Services::Base
  def model; Community; end

  # Mirrors lib/data/communities.js: search by name, plus filters for the
  # three FKs (builder/area/location) and status, and the Active/Archived
  # scope shared by every Property Catalog resource so far.
  SORTABLE_COLUMNS = %w[name price_min created_at status].freeze

  def list
    ds = model
    ds = ds.where(archived: qs[:archived].to_s == 'true') if qs.key?(:archived)
    ds = ds.where(builder_id: qs[:builder_id]) if qs[:builder_id].present?
    ds = ds.where(area_id: qs[:area_id]) if qs[:area_id].present?
    ds = ds.where(location_id: qs[:location_id]) if qs[:location_id].present?
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    if qs[:search].present?
      ds = ds.where(Sequel.like(:name, "%#{qs[:search]}%", case_insensitive: true))
    end
    # routes.rb mounts this exact same class/method for both the admin
    # ('communities', admin_required!-gated) and public ('public'/
    # 'communities', no auth at all) routes — `App.cu.staff?` is the only
    # signal available to tell which one is calling, and it's reliable here
    # since the admin mount can't be reached at all without a valid staff
    # session. An admin always sees every community regardless of live
    # inventory (so they can find and add properties to a sold-out or
    # not-yet-listed one); the public route never sees one with nothing a
    # visitor could actually buy.
    ds = ds.where(archived: false, id: live_community_ids) unless App.cu.staff?
    ds = apply_sort(ds, SORTABLE_COLUMNS, default: [[:created_at, :desc]])

    # Opt-in: same non-breaking contract as Properties#list — no `page`
    # param means the exact bare-array response every existing caller
    # already gets.
    stats = community_stats
    paginated_response(ds) { |c| c.to_pos.merge(stats[c.id] || default_stats) }
  end

  def get
    if !App.cu.staff? && (item.archived || !has_live_properties?(item.id))
      return_errors!('Community not found.', 404)
    end
    stats = community_stats(item.id)
    return_success(item.to_pos.merge(stats[item.id] || default_stats))
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
        :slug, :name, :builder_id, :area_id, :location_id, :tagline, :status, :rera_status,
        :featured, :trending, :homepage_visibility, :rera, :price_min, :price_max,
        :unit_types, :total_units, :available_units, :possession, :investment_score,
        :growth_pct, :last_price_update, :hero_image, :gallery, :overview, :master_plan,
        :master_plan_image, :floor_plans, :amenity_ids, :pricing_trend, :nearby, :documents,
        :seo, :archived
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

  def default_stats
    { 'rating' => 0, 'review_count' => 0, 'property_count' => 0 }
  end

  # A community's rating is derived, not stored — real buyers review the
  # specific community they bought into (see services/client_reviews.rb's
  # `owns?`), so `rating`/`review_count` are the average/count of every
  # Approved review with `reviewable_type: 'Community'`. `property_count` is
  # what the frontend uses to block deleting a community that still has
  # properties attached (same "reassign first" UX as Areas/Builders). Pass
  # `community_id` to scope to a single community (`get`); omit it to
  # compute every community at once (`list`), same "group once, merge into
  # each row" convention as Areas#stats_by_area / Builders#builder_stats.
  def community_stats(community_id = nil)
    reviews = Review.where(reviewable_type: 'Community', status: 'Approved')
    reviews = reviews.where(reviewable_id: community_id) if community_id
    stars_by_community = Hash.new { |h, k| h[k] = [] }
    reviews.select(:reviewable_id, :stars).each { |r| stars_by_community[r.reviewable_id] << r.stars }

    # `property_count` excludes Archived listings from the catalog count the
    # same way it always did — `publish_status` is the single source of
    # truth now (see models/property.rb), so this reads that instead of the
    # old, now-retired `archived` boolean.
    property_scope = Property.exclude(publish_status: 'Archived')
    property_scope = property_scope.where(community_id: community_id) if community_id
    property_counts = property_scope.group_and_count(:community_id).as_hash(:community_id, :count)

    community_ids = (stars_by_community.keys + property_counts.keys).uniq
    community_ids.each_with_object({}) do |id, out|
      stars = stars_by_community[id] || []
      out[id] = {
        'rating' => stars.empty? ? 0 : (stars.sum.to_f / stars.size).round(1),
        'review_count' => stars.size,
        'property_count' => property_counts[id] || 0,
      }
    end
  end

  # "Has properties" for a public visitor means has something actually
  # purchasable right now — Published and not Sold, the same definition that
  # already decides whether a property shows up in its own community's
  # listing grid (app/(site)/communities/[slug]/page.js's own
  # availableProperties filter, matching services/public_properties.rb's own
  # visibility rule). Only ever consulted when App.cu.staff? is false (see
  # #list/#get above) — an admin's own view is never scoped by this.
  def has_live_properties?(community_id)
    Property.where(community_id: community_id, publish_status: 'Published').exclude(status: 'Sold').first.present?
  end

  def live_community_ids
    Property.where(publish_status: 'Published').exclude(status: 'Sold').select_map(:community_id).uniq
  end

  def record_price_history!(community, change_type:, notes: nil)
    PriceHistory.create(
      community_id: community.id,
      year: Date.today.year,
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
