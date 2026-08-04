class App::Services::PropertyTypes < App::Services::Base
  def model; PropertyType; end

  # Mirrors lib/data/propertyTypes.js: the taxonomy is small and always shown
  # in its curated displayOrder, so list (unlike Builders' created_at-desc)
  # orders by display_order asc. Same search-by-name / archived-scope
  # convention as Builders#list otherwise.
  def list
    ds = model.order(:display_order, :id)
    ds = ds.where(archived: qs[:archived].to_s == 'true') if qs.key?(:archived)
    if qs[:search].present?
      ds = ds.where(Sequel.like(:name, "%#{qs[:search]}%", case_insensitive: true))
    end
    return_success(ds.all.map(&:to_pos))
  end

  # lib/data/propertyTypes.js's addPropertyType defaults displayOrder to
  # "end of the list" (propertyTypes.length + 1) when the caller doesn't pick
  # one; replicate that here rather than pushing the default onto the frontend.
  def create
    data = data_for(:save)
    data[:display_order] = data[:display_order].presence || (model.max(:display_order).to_i + 1)
    save(model.new(data))
  end

  # Archive/restore (archivePropertyType/restorePropertyType in the mock) and
  # reordering (reorderPropertyTypes) are all plain-field updates from the
  # frontend's point of view, so they ride the standard PUT/update below —
  # `archived` and `display_order` are just whitelisted like any other
  # saveable field, same pattern as Builders.
  def self.fields
    {
      save: [
        :slug, :name, :description, :icon, :banner, :image, :display_order,
        :colour, :active, :show_on_homepage, :allow_search, :seo, :archived
      ]
    }
  end
end
