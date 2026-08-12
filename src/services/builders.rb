class App::Services::Builders < App::Services::Base
  def model; Builder; end

  # Mirrors lib/data/builders.js's own filtering: search by name, and scope to
  # the Active/Archived toggle via the `archived` flag when the frontend passes
  # it as a query param (same convention as Users#list's `search`).
  SORTABLE_COLUMNS = %w[name created_at rating status].freeze

  def list
    ds = model
    ds = ds.where(archived: qs[:archived].to_s == 'true') if qs.key?(:archived)
    if qs[:search].present?
      ds = ds.where(Sequel.like(:name, "%#{qs[:search]}%", case_insensitive: true))
    end
    ds = apply_sort(ds, SORTABLE_COLUMNS, default: [[:created_at, :desc]])
    paginated_response(ds)
  end

  # Archive/restore (matching lib/data/builders.js's archiveBuilder/restoreBuilder)
  # are plain flips of the `archived` column, so they're supported through the
  # standard PUT update below rather than a dedicated action/route — `archived`
  # is just whitelisted like any other saveable field. Base#remove's "flip a
  # boolean and save" shape isn't a better fit here since it assumes an `active`
  # column; this resource models it as `archived` instead (per the mock).
  def self.fields
    {
      save: [
        :slug, :name, :established, :projects_count, :units_delivered, :rating, :status,
        :headquarters, :sqft_delivered, :website, :email, :phone, :description, :headline,
        :awards, :certifications, :documents, :logo, :seo, :archived
      ]
    }
  end
end
