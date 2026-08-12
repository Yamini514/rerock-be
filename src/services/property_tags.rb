class App::Services::PropertyTags < App::Services::Base
  def model; PropertyTag; end

  # Mirrors lib/data/propertyTags.js: a flat, uncategorised list (no
  # displayOrder/archived scope — the admin tab is just a name + colour
  # library with no archive flow), ordered alphabetically, with name search
  # same convention as every other Property Catalog resource.
  SORTABLE_COLUMNS = %w[name].freeze

  def list
    ds = model
    if qs[:search].present?
      ds = ds.where(Sequel.like(:name, "%#{qs[:search]}%", case_insensitive: true))
    end
    ds = apply_sort(ds, SORTABLE_COLUMNS, default: [[:name, :asc]])

    paginated_response(ds) { |t| with_usage(t) }
  end

  def self.fields
    {
      save: [:slug, :name, :colour]
    }
  end

  # `tag_ids` on Property is a plain Postgres integer[] (no FK,
  # migrations/0012 — see ARCHITECTURE.md), so nothing at the DB level stops
  # a delete from silently orphaning ids inside it. The admin tab's own
  # pre-delete usage check (PropertyTagsLibraryTab.js) is client-side only
  # and can be bypassed by a direct API call — this is the real,
  # unbypassable guard underneath it.
  def delete
    referenced = reference_count(item.id)
    return_errors!("Cannot delete: still used by #{referenced} propert#{referenced == 1 ? 'y' : 'ies'}.", 409) if referenced > 0
    super
  end

  private

  def reference_count(tag_id)
    Property.where(Sequel.pg_array_op(:tag_ids).contains(Sequel.pg_array([tag_id], :integer))).count
  end

  def with_usage(tag)
    tag.to_pos.merge('usage' => reference_count(tag.id))
  end
end
