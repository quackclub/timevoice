class IntegrationsController < ApplicationController
  PROVIDERS = {
    "github" => { label: "GitHub", use: "Sign in, and read PRs, commits and branches (public repos; set GITHUB_TOKEN on the server for private ones)." },
    "hackatime" => { label: "Hackatime", use: "Read your heartbeats, including file names, even with public stats turned off." },
    "hackclub" => { label: "Hack Club", use: "Sign in with your Hack Club account." },
    "google_oauth2" => { label: "Google", use: "Sign in with Google." }
  }.freeze

  def show
    authorize current_workspace, :show?

    render inertia: "Settings/Integrations", props: {
      identities: PROVIDERS.map { |provider, meta|
        identity = current_user.identity_for(provider)
        {
          provider: provider,
          label: meta[:label],
          use: meta[:use],
          available: AuthProviders.enabled?(provider),
          connected: identity.present?,
          username: identity&.username || identity&.email
        }
      },
      server: {
        github_token: ENV["GITHUB_TOKEN"].present?,
        hackatime_api_key: ENV["HACKATIME_API_KEY"].present? && ENV["HACKATIME_API_KEY_EMAIL"].to_s.casecmp?(current_user.email),
        cloudflare: ENV["CLOUDFLARE_API_TOKEN"].present? && ENV["CLOUDFLARE_ACCOUNT_ID"].present?,
        vercel: ENV["VERCEL_TOKEN"].present?
      }
    }
  end

  def connect
    provider = params[:provider].to_s
    unless PROVIDERS.key?(provider) && AuthProviders.enabled?(provider)
      redirect_to "/#{current_workspace.hashid}/settings/integrations", alert: "That provider is not set up on this server."
      return
    end
    session[:connect_return_to] = "/#{current_workspace.hashid}/settings/integrations"
    redirect_to "/auth/#{provider}", allow_other_host: false
  end
end
