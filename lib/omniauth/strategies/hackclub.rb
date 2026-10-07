require "omniauth-oauth2"

module OmniAuth
  module Strategies
    class Hackclub < OmniAuth::Strategies::OAuth2
      option :name, "hackclub"
      option :client_options, {
        site: "https://auth.hackclub.com",
        authorize_url: "/oauth/authorize",
        token_url: "/oauth/token"
      }
      option :scope, "openid profile"
      option :pkce, true

      uid { raw_info["sub"] }

      info do
        {
          name: raw_info["name"].presence || [ raw_info["given_name"], raw_info["family_name"] ].compact.join(" ").presence || raw_info["nickname"],
          email: raw_info["email"],
          nickname: raw_info["nickname"],
          image: nil
        }
      end

      extra { { raw_info: raw_info } }

      def raw_info
        @raw_info ||= access_token.get("/oauth/userinfo").parsed
      end

      def callback_url
        full_host + callback_path
      end
    end
  end
end
