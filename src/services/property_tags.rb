class App::Services::PropertyTags < App::Services::Base
  def model; PropertyTag; end

  # Mirrors lib/data/propertyTags.js: a flat, uncategorised list (no
  # displayOrder/archived scope — the admin tab is just a name + colour
  # library with no archive flow), ordered alphabetically, with name search
  # same convention as every other Property Catalog resource.
  def list
    ds = model.order(:name)
    if qs[:search].present?
      ds = ds.where(Sequel.like(:name, "%#{qs[:search]}%", case_insensitive: true))
    end
    return_success(ds.all.map(&:to_pos))
  end

  def self.fields
    {
      save: [:slug, :name, :colour]
    }
  end
end
