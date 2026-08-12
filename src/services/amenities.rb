class App::Services::Amenities < App::Services::Base
  def model; Amenity; end

  # Mirrors lib/data/amenities.js: no curated displayOrder or archived scope
  # for this resource (the admin tab has neither an archive flow nor manual
  # reordering — just an Active/Inactive status column), so this is ordered
  # alphabetically instead. Supports name search and an exact category filter
  # (categories are the fixed AMENITY_CATEGORIES list on the frontend), same
  # search-and-filter convention as every other Property Catalog resource.
  SORTABLE_COLUMNS = %w[name category].freeze

  def list
    ds = model
    ds = ds.where(category: qs[:category]) if qs[:category].present?
    if qs[:search].present?
      ds = ds.where(Sequel.like(:name, "%#{qs[:search]}%", case_insensitive: true))
    end
    ds = apply_sort(ds, SORTABLE_COLUMNS, default: [[:name, :asc]])

    paginated_response(ds) { |a| with_usage(a) }
  end

  def self.fields
    {
      save: [:slug, :name, :icon, :category, :active]
    }
  end

  # `amenity_ids` on both Property and Community is a plain Postgres
  # integer[] (no FK, migrations/0011 & 0012 — see ARCHITECTURE.md), so
  # nothing at the DB level stops a delete from silently orphaning ids
  # inside those arrays. The admin tab's own pre-delete usage check
  # (AmenitiesLibraryTab.js) is client-side only and can be bypassed by a
  # direct API call — this is the real, unbypassable guard underneath it.
  def delete
    referenced_properties, referenced_communities = reference_counts(item.id)
    if referenced_properties > 0 || referenced_communities > 0
      return_errors!(
        "Cannot delete: still used by #{referenced_properties} propert#{referenced_properties == 1 ? 'y' : 'ies'} and #{referenced_communities} communit#{referenced_communities == 1 ? 'y' : 'ies'}.",
        409
      )
    end
    super
  end

  private

  def reference_counts(amenity_id)
    matcher = Sequel.pg_array_op(:amenity_ids).contains(Sequel.pg_array([amenity_id], :integer))
    [Property.where(matcher).count, Community.where(matcher).count]
  end

  def with_usage(amenity)
    properties_count, communities_count = reference_counts(amenity.id)
    amenity.to_pos.merge('usage' => properties_count + communities_count)
  end
end
