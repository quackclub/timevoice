module Activity
  # Three independent estimates of time worked, for comparing against billed time:
  #   items    - every commit, PR, branch, deploy and review gets a cost in minutes
  #   sessions - git-hours: events closer than the session gap are one session, plus a lead-in
  #   coded    - Hackatime coding time
  # The activity dashboard runs the same maths in the browser (app/frontend/lib/estimates.ts)
  # so the weights can be edited live; keep the two in step.
  class Estimator
    DEFAULT_WEIGHTS = {
      commit_base: 8, per_line: 0.1, line_cap: 400, commit_cap: 45, repeated_commit: 1,
      merge_branch: 2, squash: 3, pr: 12, reviewed: 15, branch: 1, deploy: 4,
      session_gap: 30, lead_in: 15
    }.freeze

    def initialize(events, timezone:, weights: {})
      @events = events.sort_by(&:occurred_at)
      @zone = ActiveSupport::TimeZone[timezone.presence || "UTC"] || Time.zone
      @w = DEFAULT_WEIGHTS.merge(weights.to_h.symbolize_keys.slice(*DEFAULT_WEIGHTS.keys).transform_values(&:to_f))
    end

    def item_minutes(event, repeated: false)
      m = event.metadata || {}
      case event.kind
      when "commit", "main"
        return @w[:merge_branch] if m["merge_branch"]
        return @w[:repeated_commit] if repeated
        lines = [ m["additions"].to_i + m["deletions"].to_i, @w[:line_cap] ].min
        [ @w[:commit_base] + @w[:per_line] * lines, @w[:commit_cap] ].min
      when "merge" then @w[:squash]
      when "pr" then @w[:pr]
      when "reviewed" then @w[:reviewed]
      when "branch" then @w[:branch]
      when "deploy" then @w[:deploy]
      else 0
      end
    end

    # => { Date => { items:, sessions:, coded: } } in seconds
    def by_day
      days = Hash.new { |h, k| h[k] = { items: 0.0, sessions: 0.0, coded: 0.0 } }
      seen = Set.new
      @events.each do |e|
        day = local_day(e.occurred_at)
        if e.kind == "coding"
          days[day][:coded] += e.duration_seconds.to_i
          next
        end
        key = "#{day}|#{e.title}"
        repeated = e.kind.in?(%w[commit main]) && seen.include?(key)
        seen << key
        days[day][:items] += item_minutes(e, repeated: repeated) * 60
      end

      sessions.each { |start, finish| days[local_day(start)][:sessions] += (finish - start) + @w[:lead_in] * 60 }
      days
    end

    def totals
      by_day.values.each_with_object({ items: 0.0, sessions: 0.0, coded: 0.0 }) do |d, t|
        t.each_key { |k| t[k] += d[k] }
      end
    end

    private

    def local_day(time)
      time.in_time_zone(@zone).to_date
    end

    def sessions
      intervals = @events.map { |e| [ e.occurred_at, e.ended_at || e.occurred_at ] }.sort_by(&:first)
      out = []
      intervals.each do |start, finish|
        if out.any? && start - out.last[1] <= @w[:session_gap] * 60
          out.last[1] = [ out.last[1], finish ].max
        else
          out << [ start, finish ]
        end
      end
      out
    end
  end
end
