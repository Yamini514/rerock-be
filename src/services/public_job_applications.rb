require 'uri'

# Unauthenticated public job-application submission — mirrors
# services/public_contact.rb's shape exactly (validate -> create -> notify
# admin -> return_success), just against JobApplication instead of Lead.
class App::Services::PublicJobApplications < App::Services::Base
  def model; JobApplication; end

  def create
    name = params[:name]&.strip
    email = params[:email]&.strip&.downcase
    phone = params[:phone]&.strip
    job_opening_id = params[:job_opening_id].presence
    resume_url = params[:resume_url]
    cover_letter = params[:cover_letter]&.strip

    return_errors!("Name is required.", 400) if name.blank?
    return_errors!("Enter a valid email address.", 400) if email.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)
    return_errors!("Phone number is required.", 400) if phone.blank?

    job_opening = job_opening_id.present? ? JobOpening[job_opening_id] : nil

    application = JobApplication.new(
      job_opening_id: job_opening&.id,
      name: name,
      email: email,
      phone: phone,
      resume_url: resume_url,
      cover_letter: cover_letter,
      status: 'New'
    )

    save(application) do |o|
      Notification.create(
        audience: 'admin',
        type: 'career',
        icon: 'Briefcase',
        title: 'New job application',
        message: "#{o.name} applied#{job_opening ? " for #{job_opening.title}" : ''}."
      )
      return_success('Thanks! We\'ll review your application and be in touch.')
    end
  end
end
