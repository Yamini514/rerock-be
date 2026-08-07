class App::Models::SiteVisit < Sequel::Model
  many_to_one :lead
  many_to_one :property
  many_to_one :community

  # Called after every save from both the admin (services/site_visits.rb)
  # and agent-portal (services/agent_portal.rb#update_my_site_visit) update
  # paths. Idempotent — the `Deal.where(site_visit_id: id).first` guard
  # means a re-save of an already-Completed visit (e.g. editing notes
  # afterward) never creates a second Deal. Seeds the Deal's own `notes`
  # from the visit's notes as a starting point; from there it's an
  # independent, directly-editable field (see services/deals.rb).
  def ensure_deal_for_completion!
    return unless status == 'Completed'
    return if App::Models::Deal.where(site_visit_id: id).first

    App::Models::Deal.create(
      site_visit_id: id,
      client_id: lead&.client_id,
      client_name: client_name,
      property_id: property_id,
      property_name: property&.title,
      agent_slug: agent_slug,
      stage: 'Opportunity',
      notes: notes
    )
  end
end
