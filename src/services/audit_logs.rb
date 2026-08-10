class App::Services::AuditLogs < App::Services::Base
  def model; AuditLog; end

  # Read + List only — routes.rb wires this service with
  # do_crud(AuditLogs, r, 'RL'), so no r.post/r.put/r.delete blocks are ever
  # registered for 'audit-logs'. This table is a polymorphic database change
  # log (old value -> new value per entity field); it is system-generated and
  # deliberately has no admin-facing create/update/delete, same as Activity Logs.
  #
  # Filters mirror lib/data/auditLogs.js's own filter UI: exact matches on
  # module/entity, a created_at date-range (the natural "timestamp" field —
  # see the migration), and a search across changed_by/entity_id (the columns
  # an admin would actually recognize a change by).
  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(module: qs[:module]) if qs[:module].present?
    ds = ds.where(entity: qs[:entity]) if qs[:entity].present?
    ds = ds.where(entity_id: qs[:entity_id]) if qs[:entity_id].present?
    ds = ds.where { created_at >= qs[:date_from] } if qs[:date_from].present?
    ds = ds.where { created_at <= qs[:date_to] } if qs[:date_to].present?

    # RAM Details page's Activities tab: a real cross-entity feed for one RAM
    # member built entirely out of this already-populated, already-generic
    # table — no new columns, no new writer. `entity_id` is stored as a
    # string (Base#write_audit_row!), so the two subquery id lists are mapped
    # to strings to match. An unknown ram_id intentionally returns zero rows
    # (Sequel[false]) rather than silently falling back to the unfiltered list.
    if qs[:ram_id].present?
      ram = RamMember[qs[:ram_id]]
      if ram
        referral_ids = Referral.where(ram_id: ram.slug).select_map(:id).map(&:to_s)
        commission_ids = Commission.where(ram_id: ram.slug).select_map(:id).map(&:to_s)
        ds = ds.where(
          (Sequel[entity: 'RamMember'] & Sequel[entity_id: ram.id.to_s]) |
          (Sequel[entity: 'Referral'] & Sequel[entity_id: referral_ids]) |
          (Sequel[entity: 'Commission'] & Sequel[entity_id: commission_ids])
        )
      else
        ds = ds.where(false)
      end
    end

    if qs[:search].present?
      # Same `Dataset#or` pitfall documented in leads.rb/site_visits.rb/
      # activity_logs.rb: `Dataset#or` ORs the new condition against the
      # dataset's *entire* existing WHERE clause, which would silently drop
      # the module/entity/entity_id/date-range filters above whenever a
      # search term is also present. Combine the OR conditions with `|`
      # first, then AND the whole thing into the already-filtered dataset.
      term = "%#{qs[:search]}%"
      ds = ds.where(
        Sequel.like(:changed_by, term, case_insensitive: true) |
        Sequel.like(:entity_id, term, case_insensitive: true)
      )
    end
    if qs.key?(:page)
      total = ds.count
      return_success(ds.limit(limit).offset(offset).all.map(&:to_pos), meta: { total: total, page: (qs[:page] || 1).to_i, page_size: page_size })
    else
      return_success(ds.all.map(&:to_pos))
    end
  end

  # Not reachable via routes.rb (do_crud only wires 'RL' for this resource),
  # but kept as a real whitelist in case a future internal writer (some other
  # service logging a change against this table directly) needs one — same
  # reasoning as activity_logs.rb's self.fields. NOTE: nothing in this
  # codebase currently writes to this table via this whitelist — see the
  # "Ops/Logs — Audit Logs" section of ARCHITECTURE.md for the follow-up
  # scope (per-module automatic audit-log writing on real create/update/
  # delete) that isn't built yet.
  def self.fields
    {
      save: [
        :module, :entity, :entity_id, :changed_by, :old_value, :new_value,
        :ip, :device
      ]
    }
  end
end
