class App::Services::Reviews < App::Services::Base
  def model; Review; end

  REVIEWABLE_TYPES = %w[Agent RamMember Property Builder Community].freeze

  # Admin moderation queue — approve/reject are just a `status` transition
  # riding the standard PUT/update below, same "no separate action route"
  # convention as Testimonials (services/testimonials.rb).
  SORTABLE_COLUMNS = %w[stars status created_at].freeze

  def list
    ds = model
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    ds = ds.where(reviewable_type: qs[:reviewable_type]) if qs[:reviewable_type].present?
    ds = apply_sort(ds, SORTABLE_COLUMNS, default: [[:created_at, :desc], [:id, :desc]])
    paginated_response(ds)
  end

  def self.fields
    {
      save: [:reviewable_type, :reviewable_id, :stars, :quote, :status]
    }
  end
end
