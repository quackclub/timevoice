class ApplicationMailer < ActionMailer::Base
  default from: Rails.app.creds.option(:smtp, :default_from, default: "timevoice@localhost")
  layout "mailer"
end
