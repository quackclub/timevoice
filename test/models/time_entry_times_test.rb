require "test_helper"

class TimeEntryTimesTest < ActiveSupport::TestCase
  setup do
    @entry = TimeEntry.create!(user: users(:one), workspace: workspaces(:one), description: "work",
      start_at: Time.utc(2026, 10, 1, 10), end_at: Time.utc(2026, 10, 1, 11))
  end

  test "changing start and end recalculates the duration" do
    @entry.update!(start_at: Time.utc(2026, 10, 1, 9, 30), end_at: Time.utc(2026, 10, 1, 11, 15))
    assert_equal 105 * 60, @entry.reload.duration_seconds
  end

  test "end must be after start" do
    assert_not @entry.update(end_at: Time.utc(2026, 10, 1, 9))
    assert_includes @entry.errors[:end_at], "must be after the start time"
  end
end
