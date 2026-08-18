class App::Services::Leads < App::Services::Base
  def model; Lead; end

  # Opportunistic sweep, not a cron job (this backend has no scheduler infra
  # — see scripts/tasks.rb, which is just a Thor model-file generator). Runs
  # on every admin read of the leads list, same "compute/apply live" spirit
  # as FollowUp#with_overdue, except this one actually persists `archived`
  # (the requirement is real auto-archiving, not just a display flag).
  def sweep_expired_leads!
    cutoff = Time.now - (Lead::VALIDITY_DAYS * 24 * 60 * 60)
    model.where(archived: false).exclude(status: Lead::TERMINAL_STATUSES).where { created_at < cutoff }.update(archived: true)
  end

  # Mirrors lib/data/leads.js: search by client name/phone, plus exact filters
  # for status/source/priority and the FKs, ordered newest-first (there's no
  # curated display_order for leads — recency is what matters here).
  def list
    sweep_expired_leads!
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(archived: qs[:archived].to_s == 'true') if qs.key?(:archived)
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    ds = ds.where(source: qs[:source]) if qs[:source].present?
    ds = ds.where(priority: qs[:priority]) if qs[:priority].present?
    ds = ds.where(property_id: qs[:property_id]) if qs[:property_id].present?
    ds = ds.where(community_id: qs[:community_id]) if qs[:community_id].present?
    ds = ds.where(area_id: qs[:area_id]) if qs[:area_id].present?
    ds = ds.where(client_id: qs[:client_id]) if qs[:client_id].present?
    if qs[:search].present?
      term = "%#{qs[:search]}%"
      # NOTE: deliberately NOT services/users.rb's `.where(a).or(b)` idiom —
      # `Dataset#or` ORs the new condition against the dataset's *entire*
      # existing WHERE clause, which would swallow the status/source/
      # priority/property/community/area filters above whenever a search term
      # is also present (users.rb's list has no other filters, so it never
      # hit this). Combining the two LIKEs with `|` first, then ANDing the
      # combined expression in with `where`, keeps the other filters intact.
      ds = ds.where(
        Sequel.like(:client_name, term, case_insensitive: true) | Sequel.like(:client_phone, term, case_insensitive: true)
      )
    end

    # Opt-in: a caller that doesn't send `page` gets the exact bare-array
    # response every existing caller already gets — non-breaking, same
    # contract as Properties#list.
    if qs.key?(:page)
      total = ds.count
      return_success(ds.limit(limit).offset(offset).all.map(&:with_status_history), meta: { total: total, page: (qs[:page] || 1).to_i, page_size: page_size })
    else
      return_success(ds.all.map(&:with_status_history))
    end
  end

  def get
    return_success(item.with_status_history)
  end

  # Overridden (rather than left as Base#create) only to run
  # Lead#notify_agent_of_assignment! after a successful save — covers the
  # rarer case of a lead being entered with an agent already picked, same
  # as #update below covers the far more common "assign this existing
  # enquiry to an agent" action. Also writes the first `lead_status_histories`
  # row — see #update's own comment for why this table exists at all.
  def create
    data = data_for(:save)
    return_errors!("An active lead for this phone number already exists.", 409) if Lead.duplicate_active?(data[:client_phone])

    save(model.new(data)) do |o|
      o.notify_agent_of_assignment!
      LeadStatusHistory.create(lead_id: o.id, status: o.status, changed_by: audit_changed_by, notes: params[:status_note].presence)
      return_success(o.with_status_history)
    end
  end

  # Status transitions (what the old admin.js mock's "Convert to Lead" action
  # becomes — see app/admin/(portal)/enquiries/page.js) and follow-up date
  # updates all ride the standard PUT/update below. `timeline` is just
  # whitelisted like any other saveable field — the frontend sends the full,
  # already-appended array on every change (same "send the whole array back"
  # convention already used for Community#amenity_ids / Property#tag_ids,
  # just for a jsonb array of objects instead of an integer[] of ids — there's
  # no per-entry field whitelisting here, same as Property#floor_plans/
  # #pricing_trend). That jsonb column stays for freeform notes/events, but
  # it's client-supplied and trusts the client to never drop an entry — not
  # robust enough on its own for "never overwrite previous status history"
  # with a guaranteed actor. `lead_status_histories` is the real, insert-only
  # audit trail for status changes specifically: written here server-side
  # (never trusting a client-supplied history row), same "compare the
  # incoming value to the pre-save value" convention `agent_changing` below
  # already uses.
  def update(data = nil)
    data ||= data_for(:save)
    agent_changing = data.key?(:agent_slug) && data[:agent_slug] != item.agent_slug
    status_changing = data.key?(:status) && data[:status] != item.status
    item.set_fields(data, data.keys)
    save(item) do |o|
      o.notify_agent_of_assignment! if agent_changing
      LeadStatusHistory.create(lead_id: o.id, status: o.status, changed_by: audit_changed_by, notes: params[:status_note].presence) if status_changing
      return_success(o.with_status_history)
    end
  end

  def self.fields
    {
      save: [
        :client_name, :client_phone, :client_email, :avatar,
        :property_id, :community_id, :area_id, :budget,
        :source, :priority, :status, :last_follow_up, :next_follow_up,
        :agent_slug, :agent_id, :ram_id, :ram_member_id, :timeline, :archived,
        :facing, :floor_range, :quality_score, :loan_percentage
      ]
    }
  end

  # Lead -> Client conversion (POST /leads/:id/convert-to-client). Idempotent
  # — a lead that already has a client_id just returns that same Client
  # rather than erroring or creating a second one, so a double-click/retry
  # can never produce a duplicate. Dedup against an existing Client by
  # phone/email first, same "first real match wins, don't invent a new
  # contact" business rule as Base#create_referral_with_lead!'s own
  # phone/email lookup — if one exists, the lead is linked to it instead of
  # spawning a duplicate account.
  def convert_to_client
    lead = Lead[rp[:id]]
    return_errors!("Lead not found.", 404) if lead.nil?

    return return_success(lead.client.with_status_history) if lead.client_id.present?

    return_errors!("Only a Closed (won) lead can be converted to a client.", 422) unless lead.status == "Closed"
    return_errors!("This lead has no email on file — a client account needs one to log in.", 422) if lead.client_email.blank?

    existing_client = Client.where(phone: lead.client_phone).first
    existing_client ||= Client.where(email: lead.client_email).first

    client = existing_client
    temp_password = nil
    validation_errors = nil

    App.db.transaction do
      if client.nil?
        client = Client.new(
          name: lead.client_name,
          email: lead.client_email,
          phone: lead.client_phone,
          status: "Active",
          agent_id: lead.agent_id,
          assigned_agent_slug: lead.agent_slug,
          ram_member_id: lead.ram_member_id,
          assigned_ram_id: lead.ram_id,
          referral_source: lead.source,
          timeline: [{ date: Date.today.to_s, event: "Converted from Lead", note: "Converted from Lead ##{lead.id}" }]
        )
        temp_password = SecureRandom.alphanumeric(10)
        client.password = temp_password
        client.email_verified_at = Time.now
        unless client.valid?
          validation_errors = client.errors
          raise Sequel::Rollback
        end
        client.save(validate: false)
      end

      lead.client_id = client.id
      lead.save(validate: false)
    end

    return_errors!(validation_errors, 400) if validation_errors

    if temp_password
      client.send_temporary_password_email(temp_password)
      ClientStatusHistory.create(client_id: client.id, status: client.status, changed_by: audit_changed_by, notes: "Converted from Lead ##{lead.id}")
    end

    Notification.create(
      audience: "admin",
      type: "client",
      icon: "UserCheck",
      title: "Lead converted to client",
      message: "#{lead.client_name} was converted from Lead ##{lead.id} to a Client account."
    )

    return_success(client.with_status_history)
  end
end
