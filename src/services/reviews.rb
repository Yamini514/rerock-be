class App::Services::Reviews < App::Services::Base
  def model; Review; end

  REVIEWABLE_TYPES = %w[Agent RamMember Property Builder Community].freeze

  # Admin moderation queue — approve/reject are just a `status` transition
  # riding the standard PUT/update below, same "no separate action route"
  # convention as Testimonials (services/testimonials.rb).
  def list
    ds = model.order(Sequel.desc(:created_at), Sequel.desc(:id))
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    ds = ds.where(reviewable_type: qs[:reviewable_type]) if qs[:reviewable_type].present?
    return_success(ds.all.map(&:to_pos))
  end

  def self.fields
    {
      save: [:reviewable_type, :reviewable_id, :stars, :quote, :status]
    }
  end
end
