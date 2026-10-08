require "net/http"
require "json"
require "resolv"
require "ipaddr"

module TimevoiceImport
  # Talks to another Timevoice instance: OAuth authorization-code + PKCE, then the read-only API.
  class Client
    class Error < StandardError; end

    USER_AGENT = "timevoice-import/1.0".freeze
    PRIVATE_RANGES = %w[10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 127.0.0.0/8 169.254.0.0/16 100.64.0.0/10 0.0.0.0/8 ::1/128 fc00::/7 fe80::/10].map { IPAddr.new(_1) }

    # Only public https hosts: the server makes these requests, so internal addresses are off limits.
    def self.normalize_base_url(raw)
      uri = URI.parse(raw.to_s.strip.chomp("/"))
      raise Error, "Use an https:// URL for the source instance." unless uri.is_a?(URI::HTTPS) && uri.host.present?
      addresses = Resolv.getaddresses(uri.host)
      raise Error, "Could not resolve #{uri.host}." if addresses.empty?
      if addresses.any? { |a| PRIVATE_RANGES.any? { |r| r.include?(IPAddr.new(a)) } }
        raise Error, "#{uri.host} points at a private address."
      end
      "https://#{uri.host}#{":#{uri.port}" unless uri.port == 443}"
    rescue URI::InvalidURIError, IPAddr::InvalidAddressError
      raise Error, "That source URL is not valid."
    end

    def self.pkce_pair
      verifier = SecureRandom.urlsafe_base64(64)
      challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
      [ verifier, challenge ]
    end

    def self.authorize_url(base_url:, client_id:, redirect_uri:, state:, challenge:)
      query = URI.encode_www_form(client_id: client_id, redirect_uri: redirect_uri, response_type: "code", scope: "read",
        state: state, code_challenge: challenge, code_challenge_method: "S256")
      "#{base_url}/oauth/authorize?#{query}"
    end

    def initialize(base_url)
      @base = URI(base_url)
    end

    def exchange_code(code:, client_id:, client_secret:, redirect_uri:, verifier:)
      res = request(Net::HTTP::Post.new(@base + "/oauth/token").tap do |req|
        req.set_form_data(grant_type: "authorization_code", code: code, client_id: client_id,
          client_secret: client_secret, redirect_uri: redirect_uri, code_verifier: verifier)
      end)
      @token = JSON.parse(res.body).fetch("access_token")
    end

    # Everything the source exposes for one workspace. The API lists workspaces without their
    # public code, so the caller passes the code from the source's URL (e.g. /xXk2dL/timer).
    def export(workspace_code)
      code = workspace_code.to_s.strip
      raise Error, "Enter the workspace code from your old instance's address bar." if code.blank?
      data = { "me" => get("/api/v1/me") }
      %w[clients projects tags time_entries].each { |k| data[k] = get("/api/v1/#{code}/#{k}") }
      list = get("/api/v1/#{code}/invoices").fetch("invoices", [])
      data["invoices"] = list.map { |i| get("/api/v1/#{code}/invoices/#{i['hashid']}").fetch("invoice") }
      data
    end

    private

    def get(path)
      res = request(Net::HTTP::Get.new(@base + path).tap { |r| r["Authorization"] = "Bearer #{@token}" })
      JSON.parse(res.body)
    end

    def request(req)
      req["User-Agent"] = USER_AGENT
      req["Accept"] = "application/json"
      res = Net::HTTP.start(@base.host, @base.port, use_ssl: true, open_timeout: 10, read_timeout: 30) { _1.request(req) }
      return res if res.is_a?(Net::HTTPSuccess)
      hint = res.code == "404" && req.path.start_with?("/api/v1/") ? " Check the workspace code." : ""
      raise Error, "#{@base.host} answered #{res.code} for #{req.path.split('?').first}.#{hint}"
    end
  end
end
