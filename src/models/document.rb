class App::Models::Document < Sequel::Model
  many_to_one :client
  many_to_one :property

  # Called after every client-portal upload (services/client_documents.rb#create)
  # — tells the client's assigned agent a new document landed, before the
  # agent's own separate verification step (agent_portal.rb#verify_my_document)
  # even happens. Same "resolve the deferred agent_slug string to a real
  # Agent, no-op if there isn't one" convention as
  # Lead/Client#notify_of_agent_assignment! — a client with no assigned
  # agent yet (or an assignment that doesn't resolve) silently has no one
  # to tell.
  def notify_agent_of_upload!
    return if client.nil? || client.assigned_agent_slug.blank?

    agent = App::Models::Agent.where(slug: client.assigned_agent_slug).first
    return if agent.nil?

    App::Models::Notification.create(
      audience: 'agent',
      recipient_id: agent.id,
      type: 'document',
      icon: 'FileUp',
      title: 'New document uploaded',
      message: "A new document has been uploaded by #{client_name}#{property ? " for #{property.title}" : ""}."
    )
  end
end
