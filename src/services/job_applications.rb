# Admin-facing view over candidate applications (services/public_job_applications.rb
# is the actual create path — a candidate applying, not an admin). No admin
# `create` here on purpose: applications only ever originate from a real
# public submission, same "admin never fabricates a customer-originated row"
# reasoning as Leads' own public-vs-admin split (services/public_contact.rb
# vs services/leads.rb).
class App::Services::JobApplications < App::Services::Base
  def model; JobApplication; end

  def list
    ds = model.order(Sequel.desc(:created_at))
    ds = ds.where(status: qs[:status]) if qs[:status].present?
    ds = ds.where(job_opening_id: qs[:job_opening_id]) if qs[:job_opening_id].present?
    return_success(ds.all.map(&:to_pos))
  end

  # Only `status` is admin-editable — the candidate's own submitted details
  # (name/email/phone/resume/cover letter) are a factual record of what they
  # applied with and shouldn't be rewritable after the fact.
  def self.fields
    { save: [:status] }
  end
end
