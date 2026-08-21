class App::Models::Area < Sequel::Model
  one_to_many :locations

  # city/state are mandatory (validated below) so they're never blank by the
  # time we get here; country and growth_pct are the two fields the product
  # spec calls out as "optional, defaults to X if left blank" — that default
  # belongs here (runs for both create and update) rather than in
  # AreaForm.js, so the frontend never has to invent a fallback value.
  def before_validation
    self.country = 'India' if country.to_s.strip.empty?
    self.growth_pct = 0 if growth_pct.nil?
    super
  end

  # Unlike most other models here, AreaForm.js deliberately does NOT
  # duplicate these checks client-side — this validate is the single source
  # of truth for what's required/unique, and AreaForm.js just surfaces
  # whatever comes back from here. Keep it that way rather than re-adding
  # frontend-only requiredness checks.
  def validate
    super
    # `image` added to the required list so every public Area page always has
    # one to render — lib/seo.js's absoluteUrl() (rerock-frontend) crashes if
    # ever called with a null path, and the Area detail page's own JSON-LD
    # passes `area.image` straight into it with no guard of its own.
    validates_presence [:name, :city, :state, :slug, :image], message: 'is required'
    validates_unique :slug
    if name && (new? || column_changed?(:name))
      dup = self.class.where(Sequel.function(:lower, :name) => name.strip.downcase)
      dup = dup.exclude(id: id) unless new?
      errors.add(:name, 'already exists') if dup.first
    end
    validates_operator(:>=, 0, :avg_price_per_sqft) if avg_price_per_sqft
    validate_archive_guard
  end

  private

  # An Archived Area can't be quietly hidden out from under live listings —
  # same "reassign or archive them first" guard as models/community.rb's own
  # validate_archive_guard and models/builder.rb's own validate_archive_guard.
  # `publish_status != 'Archived'` matches services/areas.rb#stats_by_area's
  # own `property_count` (the single source of truth, see models/property.rb).
  def validate_archive_guard
    return unless archived && column_changed?(:archived)

    has_properties = App::Models::Property.where(area_id: id).exclude(publish_status: 'Archived').count > 0
    has_communities = App::Models::Community.where(area_id: id, archived: false).count > 0
    if has_properties || has_communities
      errors.add(:archived, 'cannot be changed while Properties or Communities are still assigned to this Area — reassign or archive them first')
    end
  end
end
