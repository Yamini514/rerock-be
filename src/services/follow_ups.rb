class App::Services::FollowUps < App::Services::Base
  def model; FollowUp; end

  # Pending (not done) first, soonest due date first — matches the mock's
  # own display order on both the standalone Follow Ups page and the
  # Dashboard's Follow Ups widget.
  def list
    ds = model.order(Sequel.asc(:done), Sequel.asc(:due_date))
    ds = ds.where(archived: qs[:archived].to_s == 'true') if qs.key?(:archived)
    ds = ds.where(done: qs[:done] == 'true') if qs[:done].present?
    ds = ds.where(agent_id: qs[:agent_id]) if qs[:agent_id].present?
    if qs[:search].present?
      ds = ds.where(Sequel.like(:client_name, "%#{qs[:search]}%", case_insensitive: true))
    end

    if qs.key?(:page)
      total = ds.count
      rows = ds.limit(limit).offset(offset).all
      return_success(rows.map(&:with_overdue), meta: { total: total, page: (qs[:page] || 1).to_i, page_size: page_size })
    else
      return_success(ds.all.map(&:with_overdue))
    end
  end

  def self.fields
    {
      save: [
        :client_name, :lead_id, :property_id, :agent_id, :due_date,
        :type, :priority, :done, :notes, :archived
      ]
    }
  end
end
