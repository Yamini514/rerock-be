
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
  def save(obj, &block)
    was_new = obj.new?
    if obj.save
      write_audit_log!(obj, was_new)
      block_given? ? yield(obj) : return_success(obj.to_pos)
    else
      return_errors!(obj.errors, 400)
    end
  rescue => e
    App.logger.error(e.message)
    App.logger.error(e.backtrace)
    return_errors!(e.message, 400)
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

  def current_client_id
    App.cu.user_obj.client_id
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
  # change to AuditLog/ActivityLog itself would be noisy at best and, if
  # anything ever routed those models through Base#save/#delete (today
  # they're wired read-only via do_crud(..., 'RL'), so nothing does),
  # recursive at worst. Compared by class name (string) rather than a
  # constant array of classes, so this doesn't depend on model
  # load-order relative to base.rb.
  AUDIT_EXCLUDED_MODELS = %w[App::Models::AuditLog App::Models::ActivityLog].freeze

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

  def audit_changed_by
    App.cu.user_obj&.full_name || 'System'
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