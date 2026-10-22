class Invoice < ApplicationRecord
  include Hashidable
  include CurrencyFormatter

  STATUSES = %w[draft issued paid].freeze
  STATUS_DRAFT = "draft".freeze
  STATUS_ISSUED = "issued".freeze
  STATUS_PAID = "paid".freeze

  belongs_to :workspace
  belongs_to :client
  has_many :invoice_lines, dependent: :destroy
  has_many :time_entries, through: :invoice_lines, source: :time_entry

  validates :period_start, presence: true
  validates :period_end, presence: true
  validates :issued_on, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :draft, -> { where(status: STATUS_DRAFT) }
  scope :issued, -> { where(status: STATUS_ISSUED) }
  scope :paid, -> { where(status: STATUS_PAID) }

  before_create :set_invoice_number

  OPTION_DEFAULTS = {
    "layout" => "simple",
    "receipt_kinds" => ActivityEvent::KINDS,
    "match" => "entry",
    "show_activity_only_days" => true,
    "reconciliation" => false
  }.freeze
  LAYOUTS = %w[simple detailed].freeze
  MATCHES = %w[entry day].freeze

  def settings
    merged = OPTION_DEFAULTS.merge((options || {}).slice(*OPTION_DEFAULTS.keys))
    merged["layout"] = "simple" unless LAYOUTS.include?(merged["layout"])
    merged["match"] = "entry" unless MATCHES.include?(merged["match"])
    merged["receipt_kinds"] = Array(merged["receipt_kinds"]) & ActivityEvent::KINDS
    merged
  end

  def detailed?
    settings["layout"] == "detailed"
  end

  def self.normalize_options(raw)
    raw = raw.to_h.stringify_keys.slice(*OPTION_DEFAULTS.keys)
    %w[show_activity_only_days reconciliation].each do |k|
      raw[k] = ActiveModel::Type::Boolean.new.cast(raw[k]) if raw.key?(k)
    end
    raw["receipt_kinds"] = Array(raw["receipt_kinds"]).map(&:to_s) & ActivityEvent::KINDS if raw.key?("receipt_kinds")
    raw
  end

  # Who the invoice is from: billing settings, falling back to the workspace owner's account.
  def sender
    setting = workspace.invoice_setting
    owner = workspace.owner
    {
      name: setting&.sender_name.presence || owner&.name,
      email: setting&.sender_email.presence || owner&.email,
      address: setting&.sender_address.presence
    }
  end

  def time_zone
    workspace.owner&.timezone.presence || "UTC"
  end

  def period_range(zone = time_zone)
    period_start.in_time_zone(zone).beginning_of_day..period_end.in_time_zone(zone).end_of_day
  end

  def activity_events
    projects = invoice_lines.filter_map { |l| l.time_entry&.project_id }.uniq
    projects |= client.projects.pluck(:id)
    users = invoice_lines.filter_map { |l| l.time_entry&.user_id }.uniq
    scope = workspace.activity_events.where(project_id: projects).between(period_range.first, period_range.last)
    scope = scope.where(user_id: users) if users.any?
    scope.where(kind: settings["receipt_kinds"]).listable.chronological.to_a
  end

  def timeline_days
    lines = invoice_lines.includes(time_entry: :project).to_a
    entries = lines.filter_map(&:time_entry)
    days = Activity::Timeline.new(
      entries: entries,
      events: activity_events,
      timezone: time_zone,
      match: settings["match"],
      kinds: settings["receipt_kinds"]
    ).days(lines: lines.index_by(&:time_entry_id))
    days = days.select { |d| d.entries.any? } unless settings["show_activity_only_days"]
    days
  end

  def estimates
    days = timeline_days
    Activity::Presenter.estimates(activity_events, timezone: time_zone, billed_by_day: days.to_h { |d| [ d.date, d.billed_seconds ] })
  end

  def total_amount
    total_cents / 100.0
  end

  def formatted_total
    format_cents(total_cents)
  end

  def self.generate_from_time_entries(workspace, client, period_start_date, period_end_date, rate_cents, user = nil, options = {})
    entries_query = TimeEntry
      .where(workspace: workspace)
      .unbilled
      .for_client(client)
      .in_date_range(period_start_date, period_end_date)

    entries_query = entries_query.where(user: user) if user

    entries = entries_query

    return nil if entries.empty?

    invoice = create!(
      workspace: workspace,
      client: client,
      period_start: period_start_date,
      period_end: period_end_date,
      issued_on: Date.current,
      status: STATUS_DRAFT,
      total_cents: 0,
      options: normalize_options(options)
    )

    total = 0

    entries.each do |entry|
      hours = entry.duration_hours
      amount = (hours * rate_cents).round

      InvoiceLine.create!(
        invoice: invoice,
        time_entry: entry,
        description: entry.description,
        qty_hours: hours,
        rate_cents: rate_cents,
        amount_cents: amount
      )

      total += amount
    end

    invoice.update!(total_cents: total)
    invoice
  end

  private

  def set_invoice_number
    self.invoice_number = (workspace.invoices.maximum(:invoice_number) || 0) + 1
  end
end
