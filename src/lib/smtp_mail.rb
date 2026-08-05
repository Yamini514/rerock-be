require "mail"
options = {
  address: ENV['SMTP_HOST'],
  port: (ENV['SMTP_PORT'] || 587).to_i,
  user_name: ENV['SMTP_USERNAME'],
  password: ENV['SMTP_PASSWORD'],
  authentication: 'plain',
  enable_starttls_auto: true  # port 587 uses STARTTLS, not implicit SSL
}

Mail.defaults do
  delivery_method :smtp, options
end



# mail = Mail.new do
#   from    'noreply@vhrr.net'
#   to      'sathish@pasupunuri.com'  # Replace with the recipient email
#   subject 'Test email'
#   body    'This is a test email sent from a Ruby Roda app!'
# end

# mail.deliver!