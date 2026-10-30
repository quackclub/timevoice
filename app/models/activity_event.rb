class ActivityEvent < ApplicationRecord
  KINDS = %w[commit main merge pr reviewed branch deploy coding].freeze
  RECEIPT_KINDS = %w[commit main merge pr reviewed branch deploy].freeze
  # Shorter coding blocks are blips (a couple of heartbeats), not work worth listing.
  MIN_CODING_SECONDS = 4.minutes.to_i
  # Coding blocks made only of AI agent heartbeats are short (one heartbeat per action), so they
  # get a lower minimum.
  SESSION_TITLE = "Coding session".freeze
  MIN_SESSION_SECONDS = 1.minute.to_i

  belongs_to :workspace
  belongs_to :user
  belongs_to :project

  validates :kind, inclusion: { in: KINDS }
  validates :source, :external_id, :occurred_at, presence: true

  scope :between, ->(from, to) { where(occurred_at: from..to) }
  scope :chronological, -> { order(:occurred_at, :id) }
  scope :listable, -> {
    where.not(kind: "coding").or(where(duration_seconds: MIN_CODING_SECONDS..))
      .or(where(kind: "coding", title: SESSION_TITLE, duration_seconds: MIN_SESSION_SECONDS..))
  }

  def listable?
    kind != "coding" || duration_seconds.to_i >= (title == SESSION_TITLE ? MIN_SESSION_SECONDS : MIN_CODING_SECONDS)
  end

  def short_ref
    return ref.to_s[0, 6] if kind.in?(%w[commit main merge deploy])
    ref
  end

  def as_timeline_json
    {
      id: id,
      kind: kind,
      source: source,
      at: occurred_at.iso8601,
      ended_at: ended_at&.iso8601,
      duration_seconds: duration_seconds,
      title: title,
      url: url,
      ref: short_ref,
      project_id: project_id,
      metadata: metadata
    }
  end
end
