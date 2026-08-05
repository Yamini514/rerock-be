# Unauthenticated, read-only, minimal-fields directory — deliberately NOT a
# do_crud(Agents, ...) reuse like Properties/Builders/Communities get in the
# 'public' block, because Agents' own #to_pos (services/agents.rb) dumps
# every column including encoded_password/current_session_id/reset_token and
# internal commission/revenue figures. This hand-picks only what's safe to
# show publicly (e.g. the Client Portal's "your assigned agent" card).
class App::Services::PublicAgents < App::Services::Base
  def model; Agent; end

  SAFE_FIELDS = %i[id slug name role phone whatsapp avatar specialization rating experience_years].freeze

  def list
    return_success(model.where(status: "Active").order(:name).all.map { |a| a.values.slice(*SAFE_FIELDS) })
  end
end
