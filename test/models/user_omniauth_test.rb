require "test_helper"

class UserOmniauthTest < ActiveSupport::TestCase
  def auth(provider, uid, email, verified: nil, nickname: nil)
    OmniAuth::AuthHash.new(
      provider: provider, uid: uid,
      info: { name: "Someone", email: email, nickname: nickname },
      credentials: { token: "tok-#{uid}" },
      extra: { raw_info: { "email_verified" => verified } }
    )
  end

  test "new GitHub sign-in creates a user and identity" do
    user = User.from_omniauth(auth("github", "42", "new@example.com", nickname: "newbie"))
    assert user.persisted?
    assert_equal "newbie", user.github_login
    assert_equal "tok-42", user.identity_for(:github).access_token
  end

  test "verified Hack Club email links to the existing account" do
    user = User.from_omniauth(auth("hackclub", "ident!abc", users(:one).email, verified: true))
    assert_equal users(:one), user
  end

  test "unverified email for an existing account is refused" do
    assert_raises(User::EmailTakenError) { User.from_omniauth(auth("github", "43", users(:one).email)) }
  end

  test "connecting an identity owned by someone else is refused" do
    User.from_omniauth(auth("github", "44", "first@example.com"))
    assert_raises(ActiveRecord::RecordNotUnique) { users(:two).connect_identity!(auth("github", "44", "x@example.com")) }
  end
end
