class SessionsController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :new, :create, :failure ]
  skip_before_action :require_workspace, only: [ :new, :create, :failure, :destroy, :disconnect ]

  layout "auth"

  CONNECT_ONLY_PROVIDERS = %w[hackatime].freeze

  def new
    redirect_to root_path if current_user
    render inertia: "Sessions/New", props: { providers: AuthProviders.sign_in_options }
  end

  def create
    auth = request.env["omniauth.auth"]

    if current_user
      connect_identity(auth)
      return
    end

    if CONNECT_ONLY_PROVIDERS.include?(auth.provider)
      redirect_to signin_path, alert: "Sign in first, then connect #{auth.provider} from settings."
      return
    end

    begin
      user = User.from_omniauth(auth)
    rescue User::EmailTakenError, ArgumentError, ActiveRecord::RecordInvalid => e
      redirect_to signin_path, alert: e.message
      return
    end
    user.create_default_workspace if user.workspaces.empty?

    session[:user_id] = user.id
    session[:workspace_id] = user.current_workspace&.id

    if (oauth_return_to = session.delete(:oauth_return_to))
      redirect_to oauth_return_to
      return
    end

    if (token = session.delete(:pending_invite_token))
      invite = Invite.valid.find_by(token: token)
      if invite && invite.email.downcase == user.email.downcase
        redirect_to invite_path(token: invite.token), notice: "Signed in! Review your invitation below."
        return
      end
    end

    redirect_to root_path, notice: "Signed in successfully!"
  end

  def destroy
    reset_session
    flash[:notice] = "Signed out successfully!"
    inertia_location signin_path
  end

  def disconnect
    identity = current_user.identities.find_by!(provider: params[:provider])
    if current_user.identities.where(provider: AuthProviders::SIGN_IN.keys).where.not(id: identity.id).none? && AuthProviders::SIGN_IN.key?(identity.provider)
      redirect_back fallback_location: root_path, alert: "You need at least one sign-in method."
      return
    end
    identity.destroy
    redirect_back fallback_location: root_path, notice: "Disconnected #{identity.provider}."
  end

  def failure
    redirect_to signin_path, alert: "Authentication failed. Please try again."
  end

  private

  def connect_identity(auth)
    current_user.connect_identity!(auth)
    redirect_to session.delete(:connect_return_to) || root_path, notice: "Connected #{auth.provider}."
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
    redirect_to session.delete(:connect_return_to) || root_path, alert: e.message
  end
end
