class App::Services::Collections < App::Services::Base
  def model; Collection; end

  # Mirrors lib/data/collections.js: a small, always-curated set of named
  # property groupings shown in displayOrder (same convention as
  # PropertyTypes#list), with name search.
  def list
    ds = model.order(:display_order, :id)
    # Additive/opt-in — the admin management table never passes `active`
    # (it needs both active and inactive rows for the toggle UI); the
    # public site's read-only consumer always passes `active=true` so
    # inactive/draft collections never leak publicly.
    ds = ds.where(active: qs[:active].to_s == 'true') if qs.key?(:active)
    if qs[:search].present?
      ds = ds.where(Sequel.like(:name, "%#{qs[:search]}%", case_insensitive: true))
    end
    return_success(ds.all.map(&:to_pos))
  end

  # addCollection defaults displayOrder to "end of the list" when the caller
  # doesn't pick one — same as PropertyTypes/Areas/Locations#create.
  def create
    data = data_for(:save)
    data[:display_order] = data[:display_order].presence || (model.max(:display_order).to_i + 1)
    save(model.new(data))
  end

  # Archive (the mock's bulk "Archive" action, a plain active:false flip) and
  # membership edits (add/removePropertyToCollection in the mock) both ride
  # the standard PUT/update below — property_ids is just whitelisted like any
  # other saveable field, same pattern as Community#amenity_ids /
  # Property#tag_ids+amenity_ids. No archived/restore column exists here
  # (unlike most other Property Catalog resources): the mock only ever had
  # `active`, no separate Archived view/restore action, so archived would be
  # dead weight.
  #
  # NOTE — "Featured Properties" special case: the mock's `id:
  # "featured-properties"` collection was a real row whose `propertyIds` was
  # kept in sync with each property's `featured` flag via the mock's
  # `toggleFeatured()`. That is deliberately NOT replicated as a stored row
  # here. Now that Properties is a real resource with its own `featured`
  # boolean column (migrations/0012), `properties.featured = true` already
  # *is* the canonical "featured properties" list — storing a second,
  # separately-maintained membership array on a `collections` row would
  # reintroduce exactly the dual-source-of-truth problem `toggleFeatured()`
  # existed to paper over, and syncing it would mean Properties#update
  # reaching into Collections on every `featured` toggle (including the bulk
  # "Mark as Featured" action on the properties list page, which updates many
  # rows with plain per-id mutate calls) — real coupling between two
  # otherwise-independent resources for no relational benefit. Instead, the
  # frontend (see app/admin/(portal)/collections/page.js and
  # [id]/CollectionDetailClient.js) renders "Featured Properties" as a
  # computed/virtual entry over `propertiesApi`'s `featured` column — it is
  # never inserted into this table, has no numeric id, and every mutation
  # against it goes straight to Properties#update instead of here.
  def self.fields
    {
      save: [:slug, :name, :description, :cover_image, :property_ids, :active, :display_order]
    }
  end
end
