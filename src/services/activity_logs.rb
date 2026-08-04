class App::Services::ActivityLogs < App::Services::Base
  def model; ActivityLog; end

  # Read + List only — routes.rb wires this service with
  # do_crud(ActivityLogs, r, 'RL'), so no r.post/r.put/r.delete blocks are
  # ever registered for 'activity-logs'. Logs are system-generated; there is
  # deliberately no admin-facing create/update/delete for this resource.
  #
  # Filters mirror lib/data/activityLogs.js's own filter UI: exact matches on
  # module/action_type/status/severity, a created_at date-range (the natural
  # "time" field — see the migration), and a search across user_name/action/
  # target (the columns an admin would actually recognize a log by).
  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(module: qs[:module]) if qs[:module].present?
    ds = ds.where(action_type: qs[:action_type]) if qs[:action_type].present?
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    ds = ds.where(severity: qs[:severity]) if qs[:severity].present?
    ds = ds.where { created_at >= qs[:date_from] } if qs[:date_from].present?
    ds = ds.where { created_at <= qs[:date_to] } if qs[:date_to].present?
    if qs[:search].present?
      # Same `Dataset#or` pitfall documented in leads.rb/site_visits.rb:
      # `Dataset#or` ORs the new condition against the dataset's *entire*
      # existing WHERE clause, which would silently drop the module/
      # action_type/status/severity/date-range filters above whenever a
      # search term is also present. Combine the OR conditions with `|`
      # first, then AND the whole thing into the already-filtered dataset.
      term = "%#{qs[:search]}%"
      ds = ds.where(
        Sequel.like(:user_name, term, case_insensitive: true) |
        Sequel.like(:action, term, case_insensitive: true) |
        Sequel.like(:target, term, case_insensitive: true)
      )
    end
    return_success(ds.all.map(&:to_pos))
  end

  # Not reachable via routes.rb (do_crud only wires 'RL' for this resource),
  # but kept as a real whitelist in case a future internal writer (some other
  # service logging an action against this table directly) needs one — same
  # reasoning as every other resource's self.fields.
  def self.fields
    {
      save: [
        :user_name, :role_name, :action, :action_type, :module, :target,
        :ip, :browser, :status, :severity
      ]
    }
  end
end
