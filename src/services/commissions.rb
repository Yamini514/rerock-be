# Admin-only CRUD over the real commissions table (migrations/0060) — the
# actual per-referral RAM commission concept, distinct from
# services/reports.rb's Commission report (an Agent-only computed view over
# agents.commission_earned, unrelated to RAM referrals). Rows are normally
# system-created (Deal#ensure_commission_for_closure!, status PENDING);
# every lifecycle step past that (approve/reject/process/mark paid,
# rate/amount corrections) is this service's own #update, gated by
# models/commission.rb's ALLOWED_TRANSITIONS state machine.
class App::Services::Commissions < App::Services::Base
  def model; Commission; end

  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(ram_id: qs[:ram_id]) if qs[:ram_id].present?
    ds = ds.where(client_id: qs[:client_id]) if qs[:client_id].present?
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    ds = ds.where(referral_id: qs[:referral_id]) if qs[:referral_id].present?
    ds = ds.where(deal_id: qs[:deal_id]) if qs[:deal_id].present?

    if qs.key?(:page)
      total = ds.count
      return_success(ds.limit(limit).offset(offset).all.map(&:to_pos), meta: { total: total, page: (qs[:page] || 1).to_i, page_size: page_size })
    else
      return_success(ds.all.map(&:to_pos))
    end
  end

  # Manual creation is the rare "backfill a deal that closed before this
  # feature existed" path — same auto-compute-unless-overridden reasoning
  # as #update below.
  def create
    data = with_computed_amount(data_for(:save), nil)
    save(model.new(data))
  end

  # Recomputes commission_amount from sale_amount x commission_rate
  # whenever either changes without commission_amount itself also being
  # explicitly sent — an admin can still directly override the final
  # amount (this feature's own commission-rule decision: "flat rate on
  # purchase, but admin can edit the payment/commission-related fields"),
  # this just keeps the two in sync unless they deliberately diverge.
  # approved_at/paid_at stamp themselves the moment status actually crosses
  # into APPROVED/PAID, rather than trusting the frontend to send a
  # timestamp — same "sensitive/derived fields aren't trusted from the
  # client" reasoning applied everywhere else in this codebase.
  def update(data = nil)
    data ||= data_for(:save)
    data = with_computed_amount(data, item)

    status_changing = data.key?(:status) && data[:status] != item.status
    if status_changing
      data = data.merge(approved_by: audit_changed_by, approved_at: Time.now) if data[:status] == 'APPROVED'
      data = data.merge(paid_at: Time.now) if data[:status] == 'PAID'
    end

    item.set_fields(data, data.keys)
    save(item) do |o|
      o.notify_of_status! if status_changing
      o.sync_referral_payout_status! if status_changing
      return_success(o.to_pos)
    end
  end

  def self.fields
    {
      save: [
        :referral_id, :deal_id, :ram_id, :ram_member_id, :client_id, :sale_amount, :commission_rate,
        :commission_amount, :status, :approved_by, :approved_at, :paid_at, :notes
      ]
    }
  end

  private

  def with_computed_amount(data, existing)
    return data unless (data.key?(:sale_amount) || data.key?(:commission_rate)) && !data.key?(:commission_amount)

    sale = (data[:sale_amount] || existing&.sale_amount || 0).to_i
    rate = (data[:commission_rate] || existing&.commission_rate || Deal::DEFAULT_COMMISSION_RATE_PCT).to_f
    data.merge(commission_amount: (sale * rate / 100.0).round)
  end
end
