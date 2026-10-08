class User < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :workspaces, through: :memberships
  has_many :owned_workspaces, class_name: "Workspace", foreign_key: :owner_id, dependent: :nullify
  has_many :time_entries, dependent: :destroy
  has_many :sent_invites, class_name: "Invite", foreign_key: :inviter_id, dependent: :destroy
  has_many :identities, dependent: :destroy
  has_many :activity_events, dependent: :destroy

  belongs_to :last_used_workspace, class_name: "Workspace", optional: true

  def pending_invites
    Invite.where("lower(email) = ?", email.downcase)
  end

  validates :email, presence: true, uniqueness: true
  validates :name, presence: true

  def self.from_omniauth(auth)
    attrs = Identity.attributes_from_omniauth(auth)
    identity = Identity.find_by(provider: auth.provider, uid: attrs[:uid])
    email = auth.info.email.presence&.downcase

    user = identity&.user
    if user.nil? && email && (existing = find_by("lower(email) = ?", email))
      raise EmailTakenError, "#{email} already has an account. Sign in with your original provider, then connect #{auth.provider} from settings." unless verified_email?(auth)
      user = existing
    end
    raise ArgumentError, "Your #{auth.provider} account has no email address." if user.nil? && email.blank?
    user ||= new(email: email, timezone: "UTC")
    user.name = auth.info.name.presence || user.name.presence || email.to_s.split("@").first
    user.avatar_url = auth.info.image if auth.info.image.present?
    user.google_uid ||= attrs[:uid] if auth.provider == "google_oauth2"

    transaction do
      user.save!
      identity ||= user.identities.find_or_initialize_by(provider: auth.provider)
      identity.update!(attrs)
    end

    user
  end

  class EmailTakenError < StandardError; end

  def self.verified_email?(auth)
    case auth.provider
    when "google_oauth2" then auth.extra&.raw_info&.dig("email_verified") != false
    when "hackclub" then auth.extra&.raw_info&.dig("email_verified") == true
    else false
    end
  end

  def connect_identity!(auth)
    attrs = Identity.attributes_from_omniauth(auth)
    existing = Identity.find_by(provider: auth.provider, uid: attrs[:uid])
    raise ActiveRecord::RecordNotUnique, "That #{auth.provider} account is linked to another user" if existing && existing.user_id != id

    identity = identities.find_or_initialize_by(provider: auth.provider)
    identity.update!(attrs)
    identity
  end

  def identity_for(provider)
    identities.find { |i| i.provider == provider.to_s }
  end

  def github_login
    identity_for(:github)&.username || identity_for(:hackatime)&.username
  end

  def create_default_workspace
    return if workspaces.any?

    workspace = Workspace.create!(
      name: "#{name}'s Workspace",
      owner: self
    )

    Membership.create!(
      user: self,
      workspace: workspace,
      role: "owner"
    )

    workspace
  end

  def current_workspace
    @current_workspace ||= workspaces.first
  end

  def self.gravatar_url(email, size: 80)
    hash = Digest::MD5.hexdigest(email.downcase.strip)
    "https://www.gravatar.com/avatar/#{hash}?s=#{size}&d=mp"
  end

  def gravatar_url(size: 80)
    self.class.gravatar_url(email, size: size)
  end

  def display_avatar_url(size: 80)
    avatar_url.presence || gravatar_url(size: size)
  end

  def admin?
    admin
  end
end
