
class App::Services::Base
  attr_reader :request

  include App::Models
  include App::Helpers

  def initialize(r)
    @request = r
  end

  def self.[](r, hash={})
    r.params.merge!(hash)
    new(r)
  end

  def json(r)
    r.to_json
  end

  def current_user
    @current_user ||= App::Helpers::CurrentUser.decoded_token
  end

  # Consider standardizing error response format
  def return_errors!(errors, code=400)
    request.halt(code, { status: 'error', data: errors })
  end

  # Consider adding validation for allowed fields
  def data_for(fn)
    allowed = a_flds[fn]
    return {} unless allowed # Add protection against missing field definitions
    
    keys = allowed[:flds].keys || []
    data = params.slice(*keys)
    allowed[:sub_flds].each do |key|
      next unless data[key].is_a?(Array) # Add protection against nil or non-array values
      data[key] = data[key].map {|d| d.slice(*allowed[:flds][key])}
    end

    data
  end

  def authorize!(*roles)
    # This method doesn't actually check anything - consider implementing real authorization
    true
  end

  def return_success(data, extras={})
    { status: 'success', data: data }.merge!(extras)
  end

  def return_success!(data, extras={})
    r.halt({ status: 'success', data: data }).merge!(extras)
  end

  # Good error handling here, but consider adding transaction support
  #
  # `was_new` is captured *before* `obj.save` runs -- once the save succeeds
  # `obj.new?` is always false, so this is the only point where "was this a
  # create or an update" can still be told apart. That flag decides whether
  # the audit write below records one create-summary row or one row per
  # changed column. See `write_audit_log!` for the actual write; it has its
  # own internal rescue so a broken audit insert can never fail this method
  # or the caller's real create/update.
  # The rescue below is scoped *only* to `obj.save` itself — deliberately not
  # wrapping the success block too. Several callers nest a second `save(...)`
  # (or a raw Notification.create/etc.) inside the block passed here (e.g.
  # services/public_site_visits.rb, services/client_site_visits.rb saving a
  # Lead, then a SiteVisit, then firing notifications, all inside one
  # another's blocks). If that rescue covered the block and something in it
  # raised, the object this call was actually responsible for had *already
  # been saved and committed* — but the caller would still get back a 400
  # "save failed" response, which is a lie: the row is really in the
  # database, the client is just wrongly told otherwise. Scoping the rescue
  # to the save call alone means a downstream failure in the continuation
  # can never misreport an already-successful save as a failure; it's the
  # caller's own job to make any further side effect in its block as safe as
  # write_audit_log!/record_price_history! already are (self-contained,
  # logged, never re-raised) if it shouldn't be able to fail the request at
  # all.
  def save(obj, &block)
    was_new = obj.new?
    begin
      saved = obj.save
    rescue => e
      App.logger.error(e.message)
      App.logger.error(e.backtrace)
      return_errors!(e.message, 400)
    end

    if saved
      write_audit_log!(obj, was_new)
      block_given? ? yield(obj) : return_success(obj.to_pos)
    else
      return_errors!(obj.errors, 400)
    end
  end

  def check_presence!(*flds)
    empty = flds.select do |f|
      params&.dig(*f).blank?
    end

    if empty.present?
      errors = empty.reduce({}) do |h, f|
        key = f.is_a?(Array) ? f.join('.') : f
        h.merge!(key => "Can't be blank")
      end
      return_errors!(errors, 400)
    end
  end

  def params
    @params ||=qs[:data]
  end

  def qs
    @qs ||= r.params.with_indifferent_access
  end

  def r; request; end
  def rp; request.params; end


  # Basic Operations

  def list
    return_success(model.order(Sequel.desc(:created_at)).all.map(&:to_pos))
  end

  def get
    return_success(item.to_pos)
  end

  def create
    obj = model.new(data_for(:save))
    save(obj)
  end

  def update(data=nil)
    data ||= data_for(:save)
    item.set_fields(data, data.keys)
    save(item)
  end

  # `audit_snapshot` is built *before* the row is actually deleted, so it
  # reflects the record as it existed right up until deletion (a compact
  # identifying summary, same style as a create's summary row -- see
  # `audit_summary`). The write itself happens only after `item.delete`
  # actually succeeds, and -- like `save` above -- can never fail this
  # method or the caller's real delete (see `write_delete_audit_log!`).
  def delete
    audit_snapshot = audit_excluded?(item) ? nil : audit_summary(item)
    res = item.delete
    if res
      write_delete_audit_log!(item, audit_snapshot) if audit_snapshot
      return_success(res.to_pos)
    else
      return_errors!('Unable to delete')
    end
  # A record another table still has a foreign key pointing at (e.g. a
  # Client with Referrals/Deals/Documents/etc. still referencing it) fails
  # at the DB level with a raw constraint-violation message — surfaced
  # as-is by the generic `rescue` below otherwise, which reads as a
  # confusing technical error rather than telling the admin why the
  # delete was refused.
  rescue Sequel::ForeignKeyConstraintViolation
    return_errors!("This #{item.class.name.split('::').last} can't be deleted because related records still reference it. Remove or reassign those first.", 409)
  rescue => e
    App.logger.error(e.message)
    App.logger.error(e.backtrace)
    return_errors!(e.message, 400)
  end

  def remove
    item.active = false
    save(item)
  end

  def item(id=rp[:id])
    @item ||= begin
      model[id] || return_errors!("No #{model.class} found with id: #{id}", 404)
    end
  end

  def add_obj
    name = r.params[:name]
    obj_id = r.params[:obj_id]
    fld = "#{name}_ids"

    obj_val = item.send(fld)

    if(obj_val)
      obj_val << obj_id
      obj_val.uniq!
    else
      item.send("#{fld}=", [obj_id])
    end
    save(item)
  end

  def remove_obj
    name = r.params[:name]
    obj_id = r.params[:obj_id]
    fld = "#{name}_ids"
    obj_val = item.send(fld)
    if(obj_val)
      item.send(fld).delete(obj_id)
    end
    save(item)
  end

  def offset
    ((qs[:page] || 1).to_i - 1) * page_size
  end

  def limit
    page_size
  end

  def page_size
    [(qs[:page_size] || 20).to_i, 300].min
  end

  # Shared dynamic-sort guard for #list overrides: `qs[:sort]` only takes
  # effect when it's in the caller's own allowlist of real, currently-visible
  # columns (never build the allowlist from client input) — this is what
  # keeps a `sort` query param from being used to inject an arbitrary column
  # into `ORDER BY`. `default` is an array of `[column, direction]` pairs
  # (lets callers like Areas/PropertyTypes keep a `[:display_order, :id]`
  # two-column default order), applied whenever `sort` is absent or not
  # allowed; a valid `sort` always resolves to a single-column order.
  def apply_sort(ds, allowed_columns, default:)
    pairs = default
    if qs[:sort].present? && allowed_columns.map(&:to_s).include?(qs[:sort].to_s)
      pairs = [[qs[:sort].to_sym, qs[:sort_dir].to_s == 'desc' ? :desc : :asc]]
    end
    ds.order(*pairs.map { |col, dir| dir == :desc ? Sequel.desc(col) : Sequel.asc(col) })
  end

  # Generalizes the opt-in `qs.key?(:page)` pagination block that used to be
  # hand-copied into every paginating #list (see properties.rb/communities.rb
  # for the original). Pass a block when a row needs more than a plain
  # `to_pos` (e.g. property_types.rb/areas.rb merge computed aggregates onto
  # each row) — those aggregate queries are grouped over the whole related
  # table in one shot, so they're unaffected by which page is being returned.
  def paginated_response(ds)
    if qs.key?(:page)
      total = ds.count
      rows = ds.limit(limit).offset(offset).all
      return_success(rows.map { |row| block_given? ? yield(row) : row.to_pos }, meta: { total: total, page: (qs[:page] || 1).to_i, page_size: page_size })
    else
      rows = ds.all
      return_success(rows.map { |row| block_given? ? yield(row) : row.to_pos })
    end
  end

  def current_client_id
    App.cu.user_obj.client_id
  end

  # Creates a Lead + Referral together in one transaction, with duplicate
  # detection and automatic Property -> Agent carry-over — the shared core
  # behind every entry point that turns a referred prospect into real CRM
  # rows: RamPortal#create_my_referral (an authenticated RAM's own manual
  # referral) and PublicContact#create/PublicSiteVisits#create (an anonymous
  # visitor converting through a RAM's shared referral link — see
  # services/public_referral_links.rb). Halts via return_errors! (400/409)
  # on failure, same as any other guard-clause-heavy service method — a
  # caller past this line can assume both records were created.
  #
  # BUSINESS DECISION (undocumented anywhere else in this codebase, so
  # recorded here): duplicate detection matches phone/email against
  # existing Clients. If a match exists AND that Client already has an
  # active referral (any status other than "Purchase Completed"/
  # "Cancelled", not archived), this 409s instead of creating a second one —
  # "first accepted referral owns the customer." A match with no active
  # referral links the new Lead/Referral to that real Client instead of
  # creating a duplicate contact.
  def create_referral_with_lead!(name:, phone:, email:, property_id:, ram_id:, referrer_name:, type:, source:, referral_link_id: nil, community_id: nil, date: nil, note: nil, budget: 0)
    return_errors!("Referred person's name is required.", 400) if name.blank?
    return_errors!("Referred person's phone number is required.", 400) if phone.blank?

    existing_client = Client.where(phone: phone).first
    existing_client ||= Client.where(email: email).first if email.present?

    if existing_client
      active_referral = Referral.where(client_id: existing_client.id, archived: false)
                                 .exclude(status: ["Purchase Completed", "Cancelled"]).first
      return_errors!("This customer already has an active referral.", 409) if active_referral
    end

    # If the property already has an assigned Agent, automatically carry
    # that assignment onto the new Lead/Referral — never invented, never
    # left for an admin to notice on their own. If the property has no
    # agent yet, agent_slug stays nil; callers surface that in their own
    # admin notification copy.
    #
    # Re-checked against a real Agent row here (not just "present?") because
    # Property#agent_slug has no DB-level FK (deferred-string convention,
    # same as Referral's own agent_slug — see models/referral.rb's comment)
    # — a renamed/deleted Agent leaves a stale slug on the property, and
    # without this guard that stale value would sail straight into the new
    # Referral, where Referral#validate's own existence check then hard-
    # fails the *visitor's* contact-form submission over an internal data
    # hygiene issue they have nothing to do with.
    property = property_id.present? ? Property[property_id] : nil
    agent_slug = property&.agent_slug
    agent_slug = nil if agent_slug.present? && Agent.where(slug: agent_slug).first.nil?

    validation_errors = nil
    lead = nil
    referral = nil

    App.db.transaction do
      lead = Lead.new(
        client_name: name,
        client_phone: phone,
        client_email: email,
        property_id: property_id,
        community_id: community_id,
        client_id: existing_client&.id,
        source: source,
        ram_id: ram_id,
        agent_slug: agent_slug,
        status: "New",
        budget: budget,
        timeline: note.present? ? [{ date: Date.today.to_s, event: "Lead created", note: note }] : []
      )
      unless lead.valid?
        validation_errors = lead.errors
        raise Sequel::Rollback
      end
      lead.save(validate: false)

      referral = Referral.new(
        ram_id: ram_id,
        type: type,
        referrer: referrer_name,
        referred: name,
        client_id: existing_client&.id,
        property_id: property_id,
        community_id: community_id,
        lead_id: lead.id,
        agent_slug: agent_slug,
        referral_link_id: referral_link_id,
        status: "Enquiry Stage",
        reward: 0,
        date: date || Time.now
      )
      unless referral.valid?
        validation_errors = referral.errors
        raise Sequel::Rollback
      end
      referral.save(validate: false)
    end

    return_errors!(validation_errors, 400) if validation_errors

    write_audit_log!(lead, true)
    write_audit_log!(referral, true)

    [lead, referral, property, agent_slug]
  end

  def to_est(time)
    # "Eastern Time (US & Canada)" is the Rails time zone name for EST/EDT.
    time.in_time_zone("Eastern Time (US & Canada)")
  end

  def format_currency(amount)
    return '$0.00' if amount.nil?

    # Convert from cents to dollars
    value = amount.to_f / 100
    # Format the value to 2 decimal places
    formatted = sprintf('%.2f', value)
    integer_part, fractional_part = formatted.split('.')
    # Insert commas for thousands separators
    integer_with_commas = integer_part.reverse.scan(/\d{1,3}/).join(',').reverse
    "$#{integer_with_commas}.#{fractional_part}"
  end

  private

  # ---------------------------------------------------------------------
  # Cross-cutting audit-log hook (App::Services::Base#save / #delete)
  #
  # Every real service inherits Base's save/delete, so wiring the write
  # here makes create/update/delete on all ~38 services auto-log to the
  # existing `audit_logs` table (migrations/0036) with zero per-service
  # changes. See ARCHITECTURE.md's "Ops/Logs -- Audit Logs" section for
  # the design writeup; this comment block covers just the "how".
  #
  # Deviation from the original mock (lib/data/auditLogs.js): that mock
  # had a fixed `AUDIT_MODULES` enum ("Users"/"Roles"/"Pricing"/etc). With
  # every module now a real, independent resource, a fixed enum would
  # either omit modules or force an ever-growing manual list. `module` is
  # instead just the entity's class name (same value as `entity`) -- e.g.
  # a Community row logs `module: "Community", entity: "Community"`. This
  # is intentionally simpler than the mock's grouping and is a documented
  # behavior change, not an oversight.
  # ---------------------------------------------------------------------

  # Models excluded from auto-audit-logging: writing an audit row about a
  # change to AuditLog itself would be noisy at best and, if anything ever
  # routed that model through Base#save/#delete (today it's wired read-only
  # via do_crud(..., 'RL'), so nothing does), recursive at worst. Compared
  # by class name (string) rather than a constant array of classes, so this
  # doesn't depend on model load-order relative to base.rb.
  AUDIT_EXCLUDED_MODELS = %w[App::Models::AuditLog].freeze

  # Columns that are either noisy (touched on nearly every save, e.g.
  # timestamps), sensitive (password/session/token material), or simply
  # not meaningful as a "changed value" (the primary key). Judgment call
  # per the task -- extend this list if another noisy/sensitive column
  # shows up in a later module.
  AUDIT_EXCLUDED_COLUMNS = %i[
    id created_at updated_at created_by updated_by created_ip updated_ip
    encoded_password password current_session_id tokens reset_token
    reset_sent_at last_logged_in_at device_uuid
  ].freeze

  def audit_excluded?(obj)
    AUDIT_EXCLUDED_MODELS.include?(obj.class.name)
  end

  # Entry point called from `save` after a successful create/update.
  # Wrapped entirely in its own rescue -- a broken audit insert must
  # never surface as a failure of the real save that just succeeded.
  def write_audit_log!(obj, was_new)
    return if audit_excluded?(obj)

    if was_new
      # A fresh row has no meaningful "field changed" semantics, so this
      # writes one summary row rather than one row per initially-set
      # column (which, thanks to the globally-enabled `:dirty` plugin,
      # `previous_changes` would otherwise show as changed from nil).
      write_audit_row!(obj, old_value: nil, new_value: audit_summary(obj))
    else
      changes = obj.previous_changes
      return if changes.blank?

      changes.each do |col, change|
        next if AUDIT_EXCLUDED_COLUMNS.include?(col.to_sym)

        old_val, new_val = change
        label = audit_label(col)
        # Field name is folded into old/new_value (e.g. "Status: Reserved"
        # -> "Status: Under Construction") rather than left bare, matching
        # lib/data/auditLogs.js's own sample rows -- the table itself has
        # no separate "which column changed" field, so without this an
        # update's audit row wouldn't say what actually changed.
        write_audit_row!(obj,
          old_value: "#{label}: #{audit_display(old_val)}",
          new_value: "#{label}: #{audit_display(new_val)}")
      end
    end
  rescue => e
    App.logger.error("[AuditLog] write failed for #{obj.class.name} ##{obj.pk}: #{e.message}")
    App.logger.error(e.backtrace)
  end

  # Entry point called from `delete` after a successful delete.
  def write_delete_audit_log!(obj, summary)
    write_audit_row!(obj, old_value: summary, new_value: nil)
  rescue => e
    App.logger.error("[AuditLog] delete-write failed for #{obj.class.name} ##{obj.pk}: #{e.message}")
    App.logger.error(e.backtrace)
  end

  # Same "must never fail the real operation that already succeeded"
  # contract as write_audit_log!/write_delete_audit_log! above — rescued and
  # logged rather than re-raised. Use for any Notification.create fired as a
  # side effect *after* the primary save an action is actually responsible
  # for has already committed. Extracted from the incident in
  # services/public_site_visits.rb / services/client_site_visits.rb: an
  # unrescued Notification.create failure was getting caught by save()'s own
  # rescue (before that rescue was narrowed to cover only the object's own
  # save — see Base#save's comment) and reported back to the client as "the
  # site visit failed to save," even though the Lead/SiteVisit had already
  # been committed.
  def notify_safely!(**attrs)
    Notification.create(**attrs)
  rescue => e
    App.logger.error("[Notification] create failed for audience=#{attrs[:audience]}: #{e.message}")
    App.logger.error(e.backtrace)
  end

  def write_audit_row!(obj, old_value:, new_value:)
    entity = obj.class.name.split('::').last
    App::Models::AuditLog.create(
      module: entity,
      entity: entity,
      entity_id: obj.pk.to_s,
      changed_by: audit_changed_by,
      old_value: old_value,
      new_value: new_value,
      ip: App.cu.ip,
      device: audit_device
    )
  end

  # Admin (App.cu) is checked first since that's who's signed in for the
  # overwhelming majority of Base#save callers (every do_crud'd admin
  # resource). RAM/Agent/Client Portal actions ride these same Base#save/
  # #delete hooks too (e.g. RamPortal#create_my_referral), but App.cu is
  # always nil there — without this fallback chain those audit rows
  # silently misattributed every RAM/Agent/Client-originated change to
  # 'System', losing the real actor's identity.
  def audit_changed_by
    App.cu.user_obj&.full_name ||
      App::Helpers::CurrentRam.ram_obj&.name ||
      App::Helpers::CurrentAgent.agent_obj&.name ||
      App::Helpers::CurrentClient.client_obj&.name ||
      'System'
  end

  # Prefers the device id captured in Before's thread-local request space
  # (helpers/before.rb's `set_did!`, off the `X-DID` header) since that's
  # already the app's existing device-identity convention (see
  # services/session.rb's own use of `App.cu.current_did`); falls back to
  # the raw User-Agent header when no device id was sent.
  def audit_device
    App.cu.current_did.presence || request.env['HTTP_USER_AGENT']
  end

  # Compact, human-readable identifying summary for a create/delete row --
  # deliberately not a full record dump (that would include giant jsonb
  # columns like `seo`/`documents`/`floor_plans`). Tries a short list of
  # common "this is what a human would recognize the record by" columns,
  # in priority order, and falls back to just the id if none are present.
  def audit_summary(obj)
    candidates = %i[name title full_name client_name slug email subject]
    pairs = candidates.each_with_object({}) do |col, h|
      next unless obj.respond_to?(col)

      val = obj.send(col)
      h[audit_label(col)] = val if val.present?
    end
    pairs = { 'Id' => obj.pk } if pairs.empty?
    pairs.map { |k, v| "#{k}: #{v}" }.join(', ')
  end

  def audit_label(col)
    col.to_s.tr('_', ' ').split(' ').map(&:capitalize).join(' ')
  end

  def audit_display(val)
    val.nil? ? 'nil' : val.to_s
  end

  def a_flds; self.class.allowed_fields; end

  def self.allowed_fields
    @allowed_fields ||= begin
      fields.with_indifferent_access.reduce({}) do |h, (action, data)|
        puts "action: #{action}"
        h.merge!(action => build_allowed_fields(data))
      end
    end.with_indifferent_access
  end

  def self.build_allowed_fields(schema, res={flds: {},  sub_flds: []})
    schema.each do |e|
      if e.is_a?(String) || e.is_a?(Symbol)
        res[:flds][e] = {}
      elsif e.is_a?(Hash)
        key, value = e.keys[0], e.values[0]
        if value.is_a?(Array)
          build_allowed_fields(value, res)
          res[:sub_flds] << key
        elsif value.is_a?(Hash)
          res[:flds].merge!(e)
        end
      end
    end
    res
  end
end