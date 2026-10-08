require "test_helper"

class Activity::EstimatorTest < ActiveSupport::TestCase
  Event = Struct.new(:kind, :occurred_at, :ended_at, :duration_seconds, :title, :metadata, keyword_init: true)

  def event(kind, at, **attrs)
    Event.new(kind: kind, occurred_at: Time.utc(2026, 9, 11, *at), metadata: {}, **attrs)
  end

  test "commit cost scales with lines up to the caps" do
    est = Activity::Estimator.new([], timezone: "UTC")
    small = event("commit", [ 10 ], title: "a", metadata: { "additions" => 10, "deletions" => 10 })
    huge = event("commit", [ 10 ], title: "b", metadata: { "additions" => 5000, "deletions" => 0 })
    assert_in_delta 10.0, est.item_minutes(small)
    assert_in_delta 45.0, est.item_minutes(huge)
  end

  test "repeated commit messages on the same day cost the repeat weight" do
    events = [
      event("commit", [ 10 ], title: "fix: same", metadata: { "additions" => 100 }),
      event("commit", [ 11 ], title: "fix: same", metadata: { "additions" => 100 })
    ]
    items = Activity::Estimator.new(events, timezone: "UTC").by_day.values.first[:items]
    assert_in_delta (18 + 1) * 60, items
  end

  test "sessions join events within the gap and add a lead-in" do
    events = [ event("pr", [ 10, 0 ]), event("branch", [ 10, 20 ]), event("deploy", [ 14, 0 ]) ]
    sessions = Activity::Estimator.new(events, timezone: "UTC").by_day.values.first[:sessions]
    assert_in_delta (20 * 60 + 15 * 60) + (15 * 60), sessions
  end

  test "coding blocks count as coded time and extend sessions" do
    events = [ event("coding", [ 9 ], ended_at: Time.utc(2026, 9, 11, 10), duration_seconds: 3000) ]
    day = Activity::Estimator.new(events, timezone: "UTC").by_day.values.first
    assert_equal 3000, day[:coded]
    assert_in_delta 3600 + 900, day[:sessions]
  end

  test "days follow the given timezone" do
    events = [ event("pr", [ 2 ]) ]
    days = Activity::Estimator.new(events, timezone: "America/New_York").by_day
    assert_equal [ Date.new(2026, 9, 10) ], days.keys
  end
end
