class Identity < ApplicationRecord
  belongs_to :user

  encrypts :access_token
  encrypts :refresh_token

  validates :provider, :uid, presence: true
  validates :uid, uniqueness: { scope: :provider }
  validates :provider, uniqueness: { scope: :user_id }

  def self.attributes_from_omniauth(auth)
    {
      uid: auth.uid.to_s,
      username: auth.info.nickname,
      email: auth.info.email,
      access_token: auth.credentials&.token,
      refresh_token: auth.credentials&.refresh_token,
      expires_at: auth.credentials&.expires_at && Time.zone.at(auth.credentials.expires_at),
      scopes: auth.credentials&.scope
    }
  end
end
