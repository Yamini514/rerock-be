class App::Services::Roles < App::Services::Base
  def model; Role; end

  # Roles are a small, curated hierarchy list (unlimited custom roles, but
  # never a paginated-list-sized set) — ordered by level (0 = highest
  # authority first), same "curated order, not created_at desc" convention
  # PropertyTypes/Areas use for their own small taxonomies. Search
  # matches either name or description; an optional exact `status` filter
  # backs an Active/Archived toggle if the frontend ever adds one (mirrors
  # every other Property-Catalog-style resource's `qs[:archived]` scope, just
  # against this resource's own `status` string column instead of a boolean).
  def list
    ds = model.order(:level, :id)
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    if qs[:search].present?
      # Combine the OR conditions with `|` before handing them to `where`, then
      # let that single call AND into the dataset — calling `Dataset#or`
      # directly here would OR against the *entire* existing WHERE clause
      # (including the status filter above) and silently widen the result set
      # whenever both a status filter and a search term are present. Same
      # `Dataset#or` pitfall already documented/fixed in services/leads.rb,
      # services/site_visits.rb, services/activity_logs.rb, etc.
      term = "%#{qs[:search]}%"
      ds = ds.where(Sequel.like(:name, term, case_insensitive: true) | Sequel.like(:description, term, case_insensitive: true))
    end
    return_success(ds.all.map(&:to_pos))
  end

  # lib/data/staff.js's addRole() derives a slug-shaped id (`role-${Date.now()}`)
  # when the caller doesn't supply one; replicate that here from the real
  # `name` field instead, same "default computed server-side rather than
  # pushed onto the frontend" convention PropertyTypes/Areas use for
  # their own defaulted fields.
  def create
    data = data_for(:save)
    data[:slug] = slugify(data[:name]) if data[:slug].blank? && data[:name].present?
    save(model.new(data))
  end

  # Archive/restore (archiveRole in the mock) and permission-matrix edits
  # (updateRolePermissions) both ride the standard PUT/update below — `status`
  # and `permissions` are just whitelisted like any other saveable field, same
  # pattern as every Property Catalog resource's archived-flag convention.
  # `is_super_admin` is included in the whitelist since it's a real column
  # (migrations/0003), but no admin-facing form exposes a control for it —
  # only the seeded "Super Admin" role ever has it set, matching the mock's
  # own behavior where isSuperAdmin isn't user-editable through the UI either.
  def self.fields
    {
      save: [:slug, :name, :level, :is_super_admin, :status, :description, :permissions]
    }
  end

  private

  def slugify(name)
    base = name.to_s.downcase.strip.gsub(/[^a-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')
    base = "role" if base.empty?
    "role-#{base}"
  end
end
