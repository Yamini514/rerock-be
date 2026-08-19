class App::Services::Builders < App::Services::Base
  def model; Builder; end

  # Mirrors lib/data/builders.js's own filtering: search by name, and scope to
  # the Active/Archived toggle via the `archived` flag when the frontend passes
  # it as a query param (same convention as Users#list's `search`). `rating`
  # dropped from here — it's no longer a real column value to sort on, see
  # `builder_stats` below.
  SORTABLE_COLUMNS = %w[name created_at status].freeze

  def list
    ds = model
    ds = ds.where(archived: qs[:archived].to_s == 'true') if qs.key?(:archived)
    if qs[:search].present?
      ds = ds.where(Sequel.like(:name, "%#{qs[:search]}%", case_insensitive: true))
    end
    ds = apply_sort(ds, SORTABLE_COLUMNS, default: [[:created_at, :desc]])
    stats = builder_stats
    paginated_response(ds) { |b| b.to_pos.merge(stats[b.id] || default_stats) }
  end

  def get
    stats = builder_stats(item.id)
    return_success(item.to_pos.merge(stats[item.id] || default_stats))
  end

  # Archive/restore (matching lib/data/builders.js's archiveBuilder/restoreBuilder)
  # are plain flips of the `archived` column, so they're supported through the
  # standard PUT update below rather than a dedicated action/route — `archived`
  # is just whitelisted like any other saveable field. Base#remove's "flip a
  # boolean and save" shape isn't a better fit here since it assumes an `active`
  # column; this resource models it as `archived` instead (per the mock).
  #
  # `rating` is deliberately NOT in this whitelist — a builder's rating is no
  # longer an admin-entered value, it's computed in `get`/`list` below from
  # real client reviews. The `rating` column still exists on the table (old
  # data, unused now) but nothing can write to it through this API anymore.
  def self.fields
    {
      save: [
        :slug, :name, :established, :projects_count, :units_delivered, :status,
        :headquarters, :sqft_delivered, :website, :email, :phone, :description, :headline,
        :awards, :certifications, :documents, :logo, :seo, :archived
      ]
    }
  end

  private

  def default_stats
    { 'rating' => 0, 'review_count' => 0, 'community_count' => 0, 'property_count' => 0 }
  end

  # One grouped pass computing everything BuilderForm.js / the admin list
  # need per builder: `rating`/`review_count` (derived, not stored — real
  # buyers review the specific Community/project they bought into, see
  # services/client_reviews.rb's `owns?`, so a builder's rating is the
  # average `stars` of every Approved review across all of its communities)
  # plus `community_count`/`property_count`, which the frontend uses to block
  # deleting a builder that's still referenced elsewhere (same
  # "reassign first" UX as Areas#stats_by_area / PropertyTypes's own guard).
  # Pass `builder_id` to scope to a single builder (`get`); omit it to
  # compute every builder at once (`list`).
  def builder_stats(builder_id = nil)
    communities = Community.select(:id, :builder_id)
    communities = communities.where(builder_id: builder_id) if builder_id
    community_builder = communities.as_hash(:id, :builder_id)

    community_counts = Hash.new(0)
    community_builder.each_value { |b_id| community_counts[b_id] += 1 }

    stars_by_builder = Hash.new { |h, k| h[k] = [] }
    unless community_builder.empty?
      Review.where(reviewable_type: 'Community', status: 'Approved', reviewable_id: community_builder.keys)
        .select(:reviewable_id, :stars).each do |r|
          b_id = community_builder[r.reviewable_id]
          stars_by_builder[b_id] << r.stars if b_id
        end
    end

    # `property_count` excludes Archived listings from the catalog count the
    # same way it always did — `publish_status` is the single source of
    # truth now (see models/property.rb), so this reads that instead of the
    # old, now-retired `archived` boolean.
    property_scope = Property.exclude(publish_status: 'Archived')
    property_scope = property_scope.where(builder_id: builder_id) if builder_id
    property_counts = property_scope.group_and_count(:builder_id).as_hash(:builder_id, :count)

    builder_ids = (community_counts.keys + property_counts.keys).uniq
    builder_ids.each_with_object({}) do |b_id, out|
      stars = stars_by_builder[b_id] || []
      out[b_id] = {
        'rating' => stars.empty? ? 0 : (stars.sum.to_f / stars.size).round(1),
        'review_count' => stars.size,
        'community_count' => community_counts[b_id] || 0,
        'property_count' => property_counts[b_id] || 0,
      }
    end
  end
end
