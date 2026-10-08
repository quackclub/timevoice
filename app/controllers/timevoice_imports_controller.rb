class TimevoiceImportsController < ApplicationController
  SESSION_KEY = :timevoice_import
  DEFAULT_SOURCE = "https://timevoice.mahadk.com".freeze

  rate_limit to: 5, within: 1.minute, only: :create, with: -> {
    redirect_to import_settings_path, alert: "Too many import attempts. Please wait a minute."
  }

  def show
    authorize current_workspace, :update?

    render inertia: "Settings/Import", props: {
      redirectUri: callback_url,
      defaultSource: DEFAULT_SOURCE,
      lastImport: session.delete(:timevoice_import_result)
    }
  end

  def create
    authorize current_workspace, :update?
    p = params.permit(:source_url, :client_id, :client_secret, :workspace_code)
    if p[:client_id].blank? || p[:client_secret].blank? || p[:workspace_code].blank?
      redirect_to import_settings_path, alert: "Fill in the client ID, client secret and workspace code."
      return
    end

    base = TimevoiceImport::Client.normalize_base_url(p[:source_url].presence || DEFAULT_SOURCE)
    verifier, challenge = TimevoiceImport::Client.pkce_pair
    state = SecureRandom.urlsafe_base64(24)
    session[SESSION_KEY] = {
      "base" => base, "client_id" => p[:client_id].strip, "client_secret" => p[:client_secret].strip,
      "workspace_code" => workspace_code_from(p[:workspace_code]),
      "state" => state, "verifier" => verifier, "workspace_id" => current_workspace.id
    }
    redirect_to TimevoiceImport::Client.authorize_url(base_url: base, client_id: p[:client_id].strip,
      redirect_uri: callback_url, state: state, challenge: challenge), allow_other_host: true
  rescue TimevoiceImport::Client::Error => e
    redirect_to import_settings_path, alert: e.message
  end

  def callback
    pending = session.delete(SESSION_KEY)
    workspace = pending && current_user.workspaces.find_by(id: pending["workspace_id"])
    if workspace.nil? || params[:state].blank? || !ActiveSupport::SecurityUtils.secure_compare(params[:state].to_s, pending["state"].to_s)
      redirect_to root_path, alert: "That import link expired. Start the import again from Settings → Import."
      return
    end
    @current_workspace = workspace
    authorize workspace, :update?

    if params[:error].present?
      redirect_to import_settings_path, alert: "The old instance said: #{params[:error_description] || params[:error]}"
      return
    end

    client = TimevoiceImport::Client.new(pending["base"])
    client.exchange_code(code: params[:code], client_id: pending["client_id"], client_secret: pending["client_secret"],
      redirect_uri: callback_url, verifier: pending["verifier"])
    data = client.export(pending["workspace_code"])
    result = TimevoiceImport::Importer.new(data, user: current_user, workspace: workspace).run

    session[:timevoice_import_result] = result.to_h.merge(source: URI(pending["base"]).host, at: Time.current.iso8601)
    redirect_to import_settings_path, notice: "Imported #{result.time_entries} time entries, #{result.invoices} invoices, " \
      "#{result.clients} clients and #{result.projects} projects."
  rescue TimevoiceImport::Client::Error, ActiveRecord::RecordInvalid, JSON::ParserError, KeyError, SocketError, Timeout::Error => e
    redirect_to import_settings_path, alert: "Import failed: #{e.message}"
  end

  private

  # Accepts the bare code ("xXk2dL") or any URL from the old instance ("https://…/xXk2dL/timer").
  def workspace_code_from(raw)
    value = raw.to_s.strip
    path = value.include?("://") ? URI.parse(value).path : value
    path.delete_prefix("/").split("/").first.to_s
  rescue URI::InvalidURIError
    value
  end

  def import_settings_path
    "/#{current_workspace.hashid}/settings/import"
  end

  def callback_url
    "#{request.base_url}/settings/import/callback"
  end
end
