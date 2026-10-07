class ActivityEvent < ApplicationRecord
  KINDS = %w[commit main merge pr reviewed branch deploy coding].freeze
  RECEIPT_KINDS = %w[commit main merge pr reviewed branch deploy].freeze

  belongs_to :workspace
  belongs_to :user
  belongs_to :project

  validates :kind, inclusion: { in: KINDS }
  validates :source, :external_id, :occurred_at, presence: true

  scope :between, ->(from, to) { where(occurred_at: from..to) }
  scope :chronological, -> { order(:occurred_at, :id) }

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
