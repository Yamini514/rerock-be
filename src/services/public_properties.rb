# Public, read-only property catalog — subclasses the real Properties
# service (services/properties.rb) purely to reuse its #filtered_dataset
# (community/builder/area/agent/status/search/bedrooms/price/rera/amenity
# filters) and #create/#update-derived #to_pos shape unchanged, just scoped
# to properties that are actually live on the public site. Properties#list/
# #get (the admin CRUD version, still mounted separately for staff) must
# keep showing every publish_status/archived state so admins can manage
# Draft/Scheduled/Archived properties — this public mount must never leak
# those. See models/property.rb's PUBLISH_STATUSES for the full state set.
class App::Services::PublicProperties < App::Services::Properties
  def list
    sync_due_scheduled_properties!
    ds = apply_sort(filtered_dataset.where(publicly_visible_scope), SORTABLE_COLUMNS, default: [[:created_at, :desc]])
    paginated_response(ds)
  end

  # Reached both by the public detail page's slug lookup (`list` above,
  # `?slug=`) and — since do_crud is mounted 'RL' here too, same as
  # PublicBuilders — a direct `GET /public/properties/:id` by numeric id.
  # Both paths must equally refuse a Draft/Scheduled(-not-yet-due)/Archived
  # property; `item` (Base#item) already 404s if the id doesn't exist at
  # all, so this only needs to add the visibility check on top.
  def get
    sync_due_scheduled_properties!
    return_errors!('Property not found.', 404) unless publicly_visible?(item)
    return_success(item.to_pos)
  end

  private

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
         .update(publish_status: 'Published')
  end

  # Published-and-not-archived is public. A Scheduled property only
  # qualifies once sync_due_scheduled_properties! has already flipped it to
  # Published above, so this scope itself never needs to inspect
  # `publish_at` — by the time it runs, "Scheduled but due" no longer
  # exists as a state in the table.
  def publicly_visible_scope
    Sequel.expr(publish_status: 'Published') & Sequel.expr(archived: false)
  end

  def publicly_visible?(property)
    property && property.publish_status == 'Published' && !property.archived
  end
end
