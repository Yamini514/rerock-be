class App::Services::Leads < App::Services::Base
  def model; Lead; end

  # Mirrors lib/data/leads.js: search by client name/phone, plus exact filters
  # for status/source/priority and the FKs, ordered newest-first (there's no
  # curated display_order for leads — recency is what matters here).
  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(archived: qs[:archived].to_s == 'true') if qs.key?(:archived)
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    ds = ds.where(source: qs[:source]) if qs[:source].present?
    ds = ds.where(priority: qs[:priority]) if qs[:priority].present?
    ds = ds.where(property_id: qs[:property_id]) if qs[:property_id].present?
    ds = ds.where(community_id: qs[:community_id]) if qs[:community_id].present?
    ds = ds.where(area_id: qs[:area_id]) if qs[:area_id].present?
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
      return_success(ds.limit(limit).offset(offset).all.map(&:to_pos), meta: { total: total, page: (qs[:page] || 1).to_i, page_size: page_size })
    else
      return_success(ds.all.map(&:to_pos))
    end
  end

  # Overridden (rather than left as Base#create) only to run
  # Lead#notify_agent_of_assignment! after a successful save — covers the
  # rarer case of a lead being entered with an agent already picked, same
  # as #update below covers the far more common "assign this existing
  # enquiry to an agent" action.
  def create
    save(model.new(data_for(:save))) do |o|
      o.notify_agent_of_assignment!
      return_success(o.to_pos)
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
  # #pricing_trend). Overridden only to run Lead#notify_agent_of_assignment!
  # after a successful save.
  def update(data = nil)
    data ||= data_for(:save)
    agent_changing = data.key?(:agent_slug) && data[:agent_slug] != item.agent_slug
    item.set_fields(data, data.keys)
    save(item) do |o|
      o.notify_agent_of_assignment! if agent_changing
      return_success(o.to_pos)
    end
  end

  def self.fields
    {
      save: [
        :client_name, :client_phone, :client_email, :avatar,
        :property_id, :community_id, :area_id, :budget,
        :source, :priority, :status, :last_follow_up, :next_follow_up,
        :agent_slug, :ram_id, :timeline, :archived
      ]
    }
  end
end
