require "test_helper"

class InvoiceTest < ActiveSupport::TestCase
  test "generate_from_time_entries filters to the provided user" do
    owner = User.create!(
      email: "invoice-owner@example.com",
      name: "Invoice Owner",
      google_uid: "invoice-owner-google-uid",
      timezone: "UTC"
    )
    teammate = User.create!(
      email: "invoice-teammate@example.com",
      name: "Invoice Teammate",
      google_uid: "invoice-teammate-google-uid",
      timezone: "UTC"
    )

    workspace = Workspace.create!(name: "Invoice Workspace", owner: owner)
    Membership.create!(workspace: workspace, user: owner, role: "owner")
    Membership.create!(workspace: workspace, user: teammate, role: "member")

    client = Client.create!(workspace: workspace, name: "Acme Corp")
    project = Project.create!(
      workspace: workspace,
      client: client,
      name: "Website Refresh",
      color: "#458588"
    )

    owner_entry = TimeEntry.create!(
      user: owner,
      workspace: workspace,
      project: project,
      description: "Owner work",
      start_at: Time.zone.parse("2026-03-01 09:00:00"),
      end_at: Time.zone.parse("2026-03-01 10:00:00"),
      billable: true
    )
    teammate_entry = TimeEntry.create!(
      user: teammate,
      workspace: workspace,
      project: project,
      description: "Teammate work",
      start_at: Time.zone.parse("2026-03-01 11:00:00"),
      end_at: Time.zone.parse("2026-03-01 12:00:00"),
      billable: true
    )

    invoice = Invoice.generate_from_time_entries(
      workspace,
      client,
      Date.new(2026, 3, 1),
      Date.new(2026, 3, 1),
      10_000,
      owner
    )

    assert_equal 1, invoice.invoice_lines.count
    assert_equal [ owner_entry.id ], invoice.invoice_lines.pluck(:time_entry_id)
    assert_equal 10_000, invoice.total_cents
    assert_empty teammate_entry.reload.invoice_lines
  end

  test "timeline and reconciliation leave out days without billed time" do
    owner = User.create!(email: "days-owner@example.com", name: "Days Owner", google_uid: "days-owner-google-uid", timezone: "UTC")
    workspace = Workspace.create!(name: "Days Workspace", owner: owner)
    Membership.create!(workspace: workspace, user: owner, role: "owner")
    client = Client.create!(workspace: workspace, name: "Days Client")
    project = Project.create!(workspace: workspace, client: client, name: "Days Project", color: "#458588")
    TimeEntry.create!(user: owner, workspace: workspace, project: project, description: "Billed work", billable: true,
      start_at: Time.zone.parse("2026-03-01 09:00:00"), end_at: Time.zone.parse("2026-03-01 10:00:00"))
    ActivityEvent.create!(workspace: workspace, user: owner, project: project, kind: "commit", source: "github",
      external_id: "billed-day", occurred_at: Time.zone.parse("2026-03-01 09:30:00"), title: "commit")
    ActivityEvent.create!(workspace: workspace, user: owner, project: project, kind: "coding", source: "hackatime",
      external_id: "unbilled-day", occurred_at: Time.zone.parse("2026-03-02 09:00:00"),
      ended_at: Time.zone.parse("2026-03-02 10:00:00"), duration_seconds: 3600, title: "coding")

    invoice = Invoice.generate_from_time_entries(workspace, client, Date.new(2026, 3, 1), Date.new(2026, 3, 3), 10_000, owner)

    assert_equal [ Date.new(2026, 3, 1) ], invoice.timeline_days.map(&:date)
    estimates = invoice.estimates
    assert_equal [ "2026-03-01" ], estimates[:days].map { |d| d[:date] }
    assert_equal 0, estimates[:totals][:coded]
  end
end
