class App::Services::Expenses < App::Services::Base
  def model; Expense; end

  # Mirrors lib/data/finance.js: search by description, plus an exact
  # category filter (the page's "Expenses by Category" breakdown groups by
  # this same column client-side over the full list).
  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(category: qs[:category]) if qs[:category].present?
    if qs[:search].present?
      term = "%#{qs[:search]}%"
      ds = ds.where(Sequel.like(:description, term, case_insensitive: true))
    end
    return_success(ds.all.map(&:to_pos))
  end

  def self.fields
    {
      save: [:category, :description, :amount, :month, :approved_by]
    }
  end
end
