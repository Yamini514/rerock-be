class App::Services::Deals < App::Services::Base
  def model; Deal; end

  # Mirrors lib/data/deals.js: search by client name, plus exact filters for
  # stage/agent_slug (the pipeline/board's own grouping + agent-scoping
  # concepts) and client_id/property_id (useful for a future Client/Property
  # detail page's "Deals" tab, same convention as Clients#list's
  # referred_by_id filter), ordered newest-first (no curated display_order
  # here, same as Leads/SiteVisits/Referrals).
  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(stage: qs[:stage]) if qs[:stage].present?
    ds = ds.where(agent_slug: qs[:agent_slug]) if qs[:agent_slug].present?
    ds = ds.where(client_id: qs[:client_id]) if qs[:client_id].present?
    ds = ds.where(property_id: qs[:property_id]) if qs[:property_id].present?
    if qs[:search].present?
      # Single search field (client_name) — no `|` combination needed, same
      # as SiteVisits#list; a plain `where` chained onto the existing dataset
      # keeps the stage/agent/client/property filters above intact.
      term = "%#{qs[:search]}%"
      ds = ds.where(Sequel.like(:client_name, term, case_insensitive: true))
    end
    return_success(ds.all.map(&:with_status_history))
  end

  def get
    return_success(item.with_status_history)
  end

  # client_name/property_name default from the linked Client/Property's own
  # name when a client_id/property_id is given but the fallback string isn't
  # explicitly passed — same "derive the denormalized string from the real
  # FK's own record" pattern as Locations#create defaulting `city` from the
  # parent Area. referral_id similarly auto-resolves when a deal is created
  # directly (not via SiteVisit#ensure_deal_for_completion!, which already
  # resolves it from the visit's own lead_id) against an existing Referral
  # for the same client — an admin can still pass an explicit referral_id
  # to override this guess.
  def create
    data = data_for(:save)
    if data[:client_name].blank? && data[:client_id].present?
      client = Client[data[:client_id]]
      data[:client_name] = client.name if client
    end
    if data[:property_name].blank? && data[:property_id].present?
      property = Property[data[:property_id]]
      data[:property_name] = property.title if property
    end
    if data[:referral_id].blank? && data[:client_id].present?
      referral = Referral.where(client_id: data[:client_id]).exclude(status: ["Purchase Completed", "Cancelled"]).first
      data[:referral_id] = referral.id if referral
    end
    save(model.new(data)) do |o|
      DealStatusHistory.create(deal_id: o.id, status: o.stage, changed_by: audit_changed_by, notes: params[:status_note].presence)
      return_success(o.with_status_history)
    end
  end

  # Stage moves (the Kanban board's inline stage Select) and probability/
  # value/closing-date edits all ride the standard PUT/update below —
  # overridden only to run Deal#ensure_commission_for_closure! and
  # #notify_client_of_closure! after a successful save, same "call
  # unconditionally, guard idempotently/by-actual-change" convention as
  # SiteVisits#update's own ensure_deal_for_completion! call.
  def update(data = nil)
    data ||= data_for(:save)
    stage_changing = data.key?(:stage) && data[:stage] != item.stage
    item.set_fields(data, data.keys)
    save(item) do |o|
      o.ensure_commission_for_closure!
      o.ensure_agent_commission_for_closure!
      o.notify_client_of_closure!
      DealStatusHistory.create(deal_id: o.id, status: o.stage, changed_by: audit_changed_by, notes: params[:status_note].presence) if stage_changing
      return_success(o.with_status_history)
    end
  end

  def self.fields
    {
      save: [
        :client_id, :client_name, :property_id, :property_name,
        :agent_slug, :referral_id, :value, :probability, :stage, :closing_date,
        :site_visit_id, :notes
      ]
    }
  end
end
