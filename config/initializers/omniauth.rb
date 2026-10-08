require Rails.root.join("lib/omniauth/strategies/hackclub").to_s
require Rails.root.join("lib/omniauth/strategies/hackatime").to_s

module AuthProviders
  ALL = %w[google_oauth2 github hackclub hackatime].freeze

  SIGN_IN = {
    "google_oauth2" => "Google",
    "github" => "GitHub",
    "hackclub" => "Hack Club"
  }.freeze

  def self.credentials(provider)
    key = provider == "google_oauth2" ? :google : provider.to_sym
    id = Rails.app.creds.option(key, :client_id)
    secret = Rails.app.creds.option(key, :client_secret)
    [ id, secret ] if id.present? && secret.present?
  end

  def self.enabled?(provider)
    credentials(provider).present?
  end

  def self.sign_in_options
    SIGN_IN.select { |provider, _| enabled?(provider) }.map { |provider, label| { provider: provider, label: label } }
  end
end

Rails.application.config.middleware.use OmniAuth::Builder do
  if (creds = AuthProviders.credentials("google_oauth2"))
    provider :google_oauth2, *creds, {
      scope: "email,profile",
      prompt: "select_account",
      image_aspect_ratio: "square",
      image_size: 200,
      name: "google_oauth2"
    }
  end

  if (creds = AuthProviders.credentials("github"))
    provider :github, *creds, scope: "read:user,user:email"
  end

  if (creds = AuthProviders.credentials("hackclub"))
    provider :hackclub, *creds
  end

  if (creds = AuthProviders.credentials("hackatime"))
    provider :hackatime, *creds
  end
end

OmniAuth.config.allowed_request_methods = [ :get, :post ]
OmniAuth.config.silence_get_warning = true
