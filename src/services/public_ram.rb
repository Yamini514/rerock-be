# Same rationale as PublicAgents (services/public_agents.rb) — hand-picked
# safe fields only, never RamMembers' own #to_pos (which dumps
# encoded_password/current_session_id/reset_token and internal KPIs).
class App::Services::PublicRam < App::Services::Base
  def model; RamMember; end

  SAFE_FIELDS = %i[id slug name designation region avatar experience_years satisfaction profile_extra].freeze

  def list
    return_success(model.where(status: "Active").order(:name).all.map { |r| r.values.slice(*SAFE_FIELDS) })
  end
end
