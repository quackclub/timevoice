module Activity
  # Groups time entries and activity events by local day for an invoice or the activity dashboard.
  # Events are attached to the time entry they happened during (with some slack either side);
  # anything left over is shown at day level.
  class Timeline
    MATCH_SLACK = 30.minutes

    Day = Struct.new(:date, :entries, :events, :billed_seconds, :coded_seconds, keyword_init: true)
    Entry = Struct.new(:entry, :line, :events, keyword_init: true)

    # outside_kinds: kinds kept when they happened outside every time entry (nil keeps all)
    def initialize(entries:, events:, timezone:, match: "entry", kinds: ActivityEvent::KINDS, outside_kinds: nil)
      @entries = entries.sort_by(&:start_at)
      @events = events
        .select { |e| kinds.include?(e.kind) }
        .select(&:listable?)
        .sort_by(&:occurred_at)
      @zone = ActiveSupport::TimeZone[timezone.presence || "UTC"] || Time.zone
      @match = match
      @outside_kinds = outside_kinds
    end

    # lines: optional map of time_entry_id => InvoiceLine so the invoice keeps its own amounts
    def days(lines: {})
      grouped = Hash.new { |h, d| h[d] = Day.new(date: d, entries: [], events: [], billed_seconds: 0, coded_seconds: 0) }

      wrapped = @entries.map { |e| Entry.new(entry: e, line: lines[e.id], events: []) }
      wrapped.each do |w|
        day = grouped[w.entry.start_at.in_time_zone(@zone).to_date]
        day.entries << w
        day.billed_seconds += w.entry.duration.to_i
      end

      @events.each do |event|
        owner = entry_for(event, wrapped)
        next if owner.nil? && @outside_kinds && !@outside_kinds.include?(event.kind)
        day = grouped[event.occurred_at.in_time_zone(@zone).to_date]
        day.coded_seconds += event.duration_seconds.to_i if event.kind == "coding"
        @match == "entry" && owner ? owner.events << event : day.events << event
      end

      grouped.values.sort_by(&:date)
    end

    private

    def entry_for(event, wrapped)
      candidates = wrapped.select do |w|
        start = w.entry.start_at - MATCH_SLACK
        finish = (w.entry.end_at || w.entry.start_at) + MATCH_SLACK
        event.occurred_at.between?(start, finish)
      end
      candidates.find { |w| w.entry.project_id == event.project_id } || candidates.first
    end
  end
end
