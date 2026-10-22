require "test_helper"

class TimevoiceImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @workspace = workspaces(:one)
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(provider: "github", uid: "gh-1",
      info: { name: @user.name, email: @user.email, nickname: "one" }, credentials: { token: "t" })
    @user.identities.create!(provider: "github", uid: "gh-1")
    get "/auth/github/callback"
  end

  teardown { OmniAuth.config.test_mode = false }

  test "start sends the user to the old instance with PKCE, and the callback imports" do
    original = TimevoiceImport::Client.method(:normalize_base_url)
    TimevoiceImport::Client.define_singleton_method(:normalize_base_url) { |url| url.chomp("/") }
    post "/#{@workspace.hashid}/settings/import",
      params: { source_url: "https://old.example.com", client_id: "cid", client_secret: "sec", workspace_code: "https://old.example.com/abc123/timer" }
    assert_response :redirect
    location = URI(response.location)
    assert_equal "old.example.com", location.host
    state = Rack::Utils.parse_query(location.query)["state"]

    data = JSON.parse(file_fixture("timevoice_export.json").read)
    calls = []
    fake = Object.new
    fake.define_singleton_method(:exchange_code) { |**kw| calls << kw; "token" }
    fake.define_singleton_method(:export) { |code| calls << code; data }
    TimevoiceImport::Client.define_singleton_method(:new) { |*| fake }
    begin
      get "/settings/import/callback", params: { code: "the-code", state: state }
    ensure
      TimevoiceImport::Client.singleton_class.remove_method(:new)
    end

    assert_redirected_to "/#{@workspace.hashid}/settings/import"
    assert_match "Imported 3 time entries", flash[:notice]
    assert_equal "sec", calls.first[:client_secret]
    assert_equal "abc123", calls.last
  ensure
    TimevoiceImport::Client.define_singleton_method(:normalize_base_url, original) if original
  end

  test "callback with a wrong state imports nothing" do
    get "/settings/import/callback", params: { code: "x", state: "forged" }
    assert_redirected_to root_path
    assert_match "expired", flash[:alert]
  end
end
