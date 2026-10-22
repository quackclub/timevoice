require "test_helper"

class Activity::TimelineTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @workspace = workspaces(:one)
    @project = projects(:one)
    @entry = TimeEntry.create!(user: @user, workspace: @workspace, project: @project, description: "ticker",
      start_at: Time.utc(2026, 9, 11, 18), end_at: Time.utc(2026, 9, 11, 19))
  end

  def event(kind, at)
    ActivityEvent.create!(workspace: @workspace, user: @user, project: @project, kind: kind, source: "github",
      external_id: SecureRandom.hex(4), occurred_at: at, title: kind)
  end

  test "events inside an entry window attach to the entry, others stay at day level" do
    inside = event("commit", Time.utc(2026, 9, 11, 19, 20))
    outside = event("pr", Time.utc(2026, 9, 11, 23))
    days = Activity::Timeline.new(entries: [ @entry ], events: [ inside, outside ], timezone: "UTC").days

    assert_equal 1, days.size
    assert_equal [ inside ], days.first.entries.first.events
    assert_equal [ outside ], days.first.events
    assert_equal 3600, days.first.billed_seconds
  end

  test "day matching keeps every event at day level" do
    inside = event("commit", Time.utc(2026, 9, 11, 18, 30))
    days = Activity::Timeline.new(entries: [ @entry ], events: [ inside ], timezone: "UTC", match: "day").days
    assert_empty days.first.entries.first.events
    assert_equal [ inside ], days.first.events
  end

  test "kinds filter drops unselected receipts" do
    branch = event("branch", Time.utc(2026, 9, 12, 10))
    days = Activity::Timeline.new(entries: [ @entry ], events: [ branch ], timezone: "UTC", kinds: %w[commit]).days
    assert_equal [ Date.new(2026, 9, 11) ], days.map(&:date)
  end

  test "coding blocks under four minutes are hidden and not counted" do
    short = ActivityEvent.create!(workspace: @workspace, user: @user, project: @project, kind: "coding", source: "hackatime",
      external_id: "short", occurred_at: Time.utc(2026, 9, 11, 10), duration_seconds: 200, title: "Coding")
    long = ActivityEvent.create!(workspace: @workspace, user: @user, project: @project, kind: "coding", source: "hackatime",
      external_id: "long", occurred_at: Time.utc(2026, 9, 11, 11), duration_seconds: 300, title: "Coding")
    day = Activity::Timeline.new(entries: [], events: [ short, long ], timezone: "UTC").days.first
    assert_equal [ long ], day.events
    assert_equal 300, day.coded_seconds
  end
end
