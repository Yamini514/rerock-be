# Public, read-only property catalog — subclasses the real Properties
# service (services/properties.rb) purely to reuse its #filtered_dataset
# (community/builder/area/agent/status/search/bedrooms/price/rera/amenity
# filters) and #create/#update-derived #to_pos shape unchanged, just scoped
# to properties that are actually live on the public site. Properties#list/
# #get (the admin CRUD version, still mounted separately for staff) must
# keep showing every publish_status so admins can manage Draft/Scheduled/
# Archived properties — this public mount must never leak those. See
# models/property.rb's PUBLISH_STATUSES for the full state set.
#
# `publish_status` is the single source of truth for public visibility —
# the old, second `archived` boolean this scope used to also check has been
# retired from that role (see models/property.rb and migrations/0097); a
# Property is now archived by setting `publish_status: 'Archived'` directly,
# so checking it here too would be checking the same fact twice.
class App::Services::PublicProperties < App::Services::Properties
  # Sold inventory has nothing left to sell, so it's excluded from the
  # browsable/searchable list (public site, and any anonymous/guest caller)
  # the same way Draft/Scheduled/Archived already are via
  # publicly_visible_scope — a buyer browsing shouldn't be shown, or have
  # recommended to them, a unit someone else already closed on.
  #
  # Two carve-outs, both resolved by the private helpers below:
  #  - Agent/RAM staff's own bulk browse+filter (no `slug` requested) keeps
  #    seeing Sold, same as before this method existed — matches their
  #    existing status filter, which already lists "Sold" as an option.
  #    Staff still can't reach a Sold property's own detail page, since
  #    that's always a `slug`-scoped request (routes.rb only exposes
  #    numeric-id lookups via #get, never by slug) and `staff_browsing?`
  #    requires `slug` to be blank.
  #  - Whoever actually owns the property (a real Closed Deal, checked in
  #    owned_property_ids below) can always resolve it, by slug or in bulk —
  #    covers the Client Portal's portfolio page (PortfolioClient.js),
  #    which requests its own held slugs here.
  def list
    sync_due_scheduled_properties!
    ds = filtered_dataset.where(publicly_visible_scope)
    ds = ds.exclude(Sequel.expr(status: 'Sold') & ~Sequel.expr(id: owned_property_ids)) unless staff_browsing?
    ds = apply_sort(ds, SORTABLE_COLUMNS, default: [[:created_at, :desc]])
    paginated_response(ds)
  end

  # Reached both by the public detail page's slug lookup (`list` above,
  # `?slug=`) and — since do_crud is mounted 'RL' here too, same as
  # PublicBuilders — a direct `GET /public/properties/:id` by numeric id.
  # Both paths must equally refuse a Draft/Scheduled(-not-yet-due)/Archived
  # property; `item` (Base#item) already 404s if the id doesn't exist at
  # all, so this only needs to add the visibility check on top. A Sold
  # property is likewise refused here unless the caller actually owns it —
  # #get is always a single-item lookup, so unlike #list above there's no
  # "staff browsing a list" carve-out that applies.
  def get
    sync_due_scheduled_properties!
    return_errors!('Property not found.', 404) unless publicly_visible?(item)
    return_errors!('Property not found.', 404) if item.status == 'Sold' && !owned_property_ids.include?(item.id)
    return_success(item.to_pos)
  end

  private

  def staff_browsing?
    qs[:slug].blank? && (App::Helpers::CurrentAgent.valid? || App::Helpers::CurrentRam.valid?)
  end

  # Real, server-verified ownership — deliberately never
  # Client#invested_properties (admin/seed-entered jsonb with no automatic
  # sync to real deals; see models/client.rb). A Closed Deal linking this
  # client to this property is the one authoritative record of an actual
  # purchase — the same record that flipped Property#status to 'Sold' in
  # the first place (models/deal.rb#sync_property_status_for_stage!).
  def owned_property_ids
    return [] unless App::Helpers::CurrentClient.valid?
    Deal.where(client_id: App::Helpers::CurrentClient.id, stage: 'Closed').exclude(property_id: nil).select_map(:property_id)
  end

  # A Scheduled property becomes Published the moment its publish_at
  # arrives (per spec: "prefer updating the database status ... when the
  # scheduled time is reached"). This app has no cron/job runner (see
  # Gemfile — no sidekiq/whenever/rufus-scheduler), so the next public
  # request is what performs that transition, right before this request's
  # own visibility check reads the row. A plain dataset #update (not
  # per-row #save) is deliberate: this is a bulk, validation-free column
  # flip on rows that are already known-valid, same as the archive/restore/
  # featured-toggle flips Properties#update already rides through.
  def sync_due_scheduled_properties!
    model.where(publish_status: 'Scheduled')
         .where { publish_at <= Sequel::CURRENT_TIMESTAMP }
         .update(publish_status: 'Published', publish_at: nil)
  end

  # Published is public — full stop. A Scheduled property only qualifies
  # once sync_due_scheduled_properties! has already flipped it to Published
  # above, so this scope itself never needs to inspect `publish_at` — by the
  # time it runs, "Scheduled but due" no longer exists as a state in the
  # table.
  def publicly_visible_scope
    Sequel.expr(publish_status: 'Published')
  end

  def publicly_visible?(property)
    property && property.publish_status == 'Published'
  end
end
