class App::Services::CareerBenefits < App::Services::Base
  def model; CareerBenefit; end

  # Mirrors lib/data/careers.js's benefits[]: no fixed sort order in the
  # mock, so newest-first same as JobOpenings. Search across title/
  # description only — no category/type concept for this resource.
  def list
    ds = model.order(Sequel.desc(:created_at), Sequel.desc(:id))
    if qs[:search].present?
      term = "%#{qs[:search]}%"
      ds = ds.where(Sequel.like(:title, term, case_insensitive: true) | Sequel.like(:description, term, case_insensitive: true))
    end
    return_success(ds.all.map(&:to_pos))
  end

  # No archive/restore/status-transition concept (same as the mock's plain
  # addBenefit/updateBenefit/deleteBenefit) — every field is a standard
  # PUT/update.
  def self.fields
    {
      save: [
        :title, :description
      ]
    }
  end
end
