# The RAM Portal's own scoped slice of the CRM — currently just the RAM's
# own assigned clients (needed so a RAM member has a real recipient list for
# services/ram_recommendations.rb), same "re-expose the admin table,
# filtered server-side to the authenticated identity" pattern as
# services/agent_portal.rb#my_clients. RAM has no deals/leads/site-visits
# scoped views today (unlike Agent), so this stays minimal rather than
# mirroring AgentPortal's full breadth speculatively.
class App::Services::RamPortal < App::Services::Base
  def current_ram
    CurrentRam.ram_obj
  end

  def my_clients
    ram = current_ram
    return_errors!("Not signed in.", 401) if ram.nil?

    return_success(Client.where(assigned_ram_id: ram.slug).order(Sequel.desc(:created_at)).all.map(&:to_pos))
  end
end
