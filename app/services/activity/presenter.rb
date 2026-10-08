module Activity
  # JSON shapes for timeline days, shared by the invoice page and the activity dashboard.
  module Presenter
    module_function

    def day(day)
      {
        date: day.date.iso8601,
        billed_seconds: day.billed_seconds,
        coded_seconds: day.coded_seconds.round,
        entries: day.entries.map { |w| entry(w) },
        events: day.events.map(&:as_timeline_json)
      }
    end

    def entry(wrapped)
      e = wrapped.entry
      line = wrapped.line
      {
        id: e.id,
        description: line&.description || e.description,
        start_at: e.start_at.iso8601,
        end_at: e.end_at&.iso8601,
        duration_seconds: e.duration.to_i,
        project: e.project && { id: e.project.id, name: e.project.name, color: e.project.color },
        qty_hours: line&.qty_hours&.to_f,
        rate: line&.formatted_rate,
        amount: line&.formatted_amount,
        events: wrapped.events.map(&:as_timeline_json)
      }
    end

    def estimates(events, timezone:, billed_by_day:)
      estimator = Estimator.new(events, timezone: timezone)
      by_day = estimator.by_day
      dates = (by_day.keys + billed_by_day.keys).uniq.sort
      {
        weights: Estimator::DEFAULT_WEIGHTS,
        days: dates.map { |d| { date: d.iso8601, billed: billed_by_day[d].to_i }.merge(by_day.fetch(d, { items: 0, sessions: 0, coded: 0 }).transform_values(&:round)) },
        totals: estimator.totals.transform_values(&:round).merge(billed: billed_by_day.values.sum)
      }
    end

    # Raw events for the browser-side estimator (lets the dashboard edit weights live)
    def estimator_events(events)
      events.map do |e|
        { kind: e.kind, at: e.occurred_at.to_f, end: (e.ended_at || e.occurred_at).to_f, title: e.title,
          secs: e.duration_seconds.to_i, add: e.metadata["additions"].to_i, del: e.metadata["deletions"].to_i,
          merge_branch: !!e.metadata["merge_branch"], ref: e.short_ref }
      end
    end
  end
end
