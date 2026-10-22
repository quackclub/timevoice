require "omniauth-oauth2"

module OmniAuth
  module Strategies
    class Hackatime < OmniAuth::Strategies::OAuth2
      option :name, "hackatime"
      option :client_options, {
        site: "https://hackatime.hackclub.com",
        authorize_url: "/oauth/authorize",
        token_url: "/oauth/token"
      }
      option :scope, "profile read"

      uid { raw_info["id"].to_s }

      info do
        {
          name: raw_info["github_username"] || raw_info["slack_id"],
          email: Array(raw_info["emails"]).first,
          nickname: raw_info["github_username"]
        }
      end

      extra { { raw_info: raw_info } }

      def raw_info
        @raw_info ||= access_token.get("/api/v1/authenticated/me").parsed
      end

      def callback_url
        full_host + callback_path
      end
    end
  end
end
