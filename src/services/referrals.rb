class App::Services::Referrals < App::Services::Base
  def model; Referral; end

  # Mirrors lib/data/referrals.js: search by referrer/referred name, plus
  # exact filters for type/status, ordered newest-first (no curated
  # display_order here either, same as Leads/SiteVisits).
  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(archived: qs[:archived].to_s == 'true') if qs.key?(:archived)
    ds = ds.where(ram_id: qs[:ram_id]) if qs[:ram_id].present?
    ds = ds.where(type: qs[:type]) if qs[:type].present?
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    ds = ds.where(client_id: qs[:client_id]) if qs[:client_id].present?
    ds = ds.where(property_id: qs[:property_id]) if qs[:property_id].present?
    ds = ds.where(agent_slug: qs[:agent_slug]) if qs[:agent_slug].present?
    # Used by the Client Detail page's own "Referrals Made" section
    # (app/admin/(portal)/clients/[id]/ClientDetailClient.js) — same
    # "exact filter, own query param" shape as ram_id above.
    ds = ds.where(referrer_client_id: qs[:referrer_client_id]) if qs[:referrer_client_id].present?
    if qs[:search].present?
      # NOTE: same fix as leads.rb/site_visits.rb — `Dataset#or` ORs the new
      # condition against the dataset's *entire* existing WHERE clause, which
      # would swallow the type/status filters above whenever a search term is
      # also present. Combining the two LIKEs with `|` first, then ANDing the
      # combined expression in with `where`, keeps the other filters intact.
      term = "%#{qs[:search]}%"
      ds = ds.where(
        Sequel.like(:referrer, term, case_insensitive: true) | Sequel.like(:referred, term, case_insensitive: true)
      )
    end

    ds = ds.eager(:client, :property, :deals, :commissions, :referrer_client)

    if qs.key?(:page)
      total = ds.count
      return_success(decorate(ds.limit(limit).offset(offset).all), meta: { total: total, page: (qs[:page] || 1).to_i, page_size: page_size })
    else
      return_success(decorate(ds.all))
    end
  end

  # Status transitions and reward/date edits all ride the standard
  # PUT/update below, overridden only to run
  # Referral#notify_referrer_of_status! after a successful save — same call
  # site as RamPortal#update_my_referral's own, since an admin (not just the
  # RAM) can also be the one who marks a referral Purchase Completed/Cancelled.
  def update(data = nil)
    data ||= data_for(:save)
    item.set_fields(data, data.keys)
    save(item) do |o|
      o.notify_referrer_of_status!
      return_success(o.to_pos)
    end
  end

  # `ram_id` filter above added for the RAM Portal's own scoped
  # `my_referrals` (services/ram_portal.rb).
  def self.fields
    {
      save: [
        :ram_id, :ram_member_id, :type, :referrer, :referred, :status, :reward, :date, :payout_status, :archived,
        :client_id, :property_id, :community_id, :lead_id, :agent_slug, :referrer_client_id
      ]
    }
  end

  private

  # Additive display fields on top of the plain to_pos dump — used by the RAM
  # Details page's Referrals tab (Customer/Property/Assigned Agent/Purchase
  # status/Commission status) but harmless for every other caller of this
  # same #list (e.g. /admin/referrals), which already resolves its own
  # display names from separately-fetched full Clients/Properties/RAM lists
  # and simply ignores these extra keys. `deals`/`commissions` come from the
  # `.eager` call above, so this is zero extra queries per row — just one
  # batched Agent lookup for the whole page.
  def decorate(rows)
    agent_slugs = rows.map(&:agent_slug).compact.uniq
    agents_by_slug = agent_slugs.empty? ? {} : Agent.where(slug: agent_slugs).select_hash(:slug, :name)

    rows.map do |r|
      latest_deal = r.deals.max_by(&:created_at)
      latest_commission = r.commissions.max_by(&:created_at)

      r.to_pos.merge(
        'customerName' => r.client&.name || r.referred,
        'propertyTitle' => r.property&.title,
        'agentName' => agents_by_slug[r.agent_slug],
        'referrerClientName' => r.referrer_client&.name,
        'purchaseStatus' => latest_deal&.stage,
        'commissionStatus' => latest_commission&.status,
        'commissionAmount' => latest_commission&.commission_amount
      )
    end
  end
end
