class ActivityController < ApplicationController
  rate_limit to: 6, within: 1.minute, only: :sync, with: -> {
    redirect_back fallback_location: activity_path, alert: "Sync is already running. Please wait a minute."
  }

  before_action { authorize current_workspace, :show? }

  def index
    zone = current_user.timezone.presence || "UTC"
    start_date = parse_date(params[:start_date]) || 30.days.ago.to_date
    end_date = parse_date(params[:end_date]) || Date.current
    from = start_date.in_time_zone(zone).beginning_of_day
    to = end_date.in_time_zone(zone).end_of_day

    entries = current_user.time_entries.where(workspace: current_workspace).completed
      .where(start_at: from..to).includes(:project)
    events = current_workspace.activity_events.where(user: current_user).between(from, to).listable.chronological.to_a
    timeline = Activity::Timeline.new(entries: entries, events: events, timezone: zone)
    days = timeline.days
    billed = days.to_h { |d| [ d.date, d.billed_seconds ] }

    render inertia: "Activity/Index", props: {
      dateRange: { start: start_date.iso8601, end: end_date.iso8601 },
      timezone: zone,
      days: days.reverse.map { |d| Activity::Presenter.day(d) },
      estimates: Activity::Presenter.estimates(events, timezone: zone, billed_by_day: billed),
      estimatorEvents: Activity::Presenter.estimator_events(events),
      projects: current_workspace.projects.order(:name).map { |p|
        p.as_json(only: [ :id, :name, :color, :activity_synced_at, :activity_sync_error ]).merge(sources: p.activity_sources?)
      }
    }
  end

  def sync
    zone = current_user.timezone.presence || "UTC"
    from = (parse_date(params[:start_date]) || 30.days.ago.to_date).in_time_zone(zone).beginning_of_day
    to = (parse_date(params[:end_date]) || Date.current).in_time_zone(zone).end_of_day

    if current_workspace.projects.none?(&:activity_sources?)
      redirect_back fallback_location: activity_path, alert: "Add GitHub repos, Hackatime projects or Workers to a project first."
      return
    end

    SyncActivityJob.perform_later(workspace_id: current_workspace.id, user_id: current_user.id, from: from.iso8601, to: to.iso8601)
    redirect_back fallback_location: activity_path, notice: "Activity sync started. Refresh in a minute to see new receipts."
  end

  private

  def activity_path
    "/#{current_workspace.hashid}/activity"
  end

  def parse_date(value)
    Date.parse(value) if value.present?
  rescue ArgumentError
    nil
  end
end
