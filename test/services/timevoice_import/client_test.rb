require "test_helper"

class TimevoiceImport::ClientTest < ActiveSupport::TestCase
  test "only public https instances are allowed" do
    assert_raises(TimevoiceImport::Client::Error) { TimevoiceImport::Client.normalize_base_url("http://example.com") }
    assert_raises(TimevoiceImport::Client::Error) { TimevoiceImport::Client.normalize_base_url("https://localhost") }
    assert_raises(TimevoiceImport::Client::Error) { TimevoiceImport::Client.normalize_base_url("https://127.0.0.1") }
    assert_raises(TimevoiceImport::Client::Error) { TimevoiceImport::Client.normalize_base_url("https://10.1.2.3/") }
  end

  test "authorize url carries PKCE and the read scope" do
    verifier, challenge = TimevoiceImport::Client.pkce_pair
    url = TimevoiceImport::Client.authorize_url(base_url: "https://old.example.com", client_id: "abc",
      redirect_uri: "https://new.example.com/settings/import/callback", state: "s", challenge: challenge)
    query = Rack::Utils.parse_query(URI(url).query)

    assert_equal "read", query["scope"]
    assert_equal "S256", query["code_challenge_method"]
    assert_equal Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false), query["code_challenge"]
  end
end
