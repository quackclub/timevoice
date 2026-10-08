require "test_helper"

class TimevoiceImport::ImporterTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @workspace = workspaces(:one)
    @data = JSON.parse(file_fixture("timevoice_export.json").read)
  end

  test "imports everything, links invoice lines to entries, and skips running timers" do
    @workspace.invoice_setting&.destroy
    result = TimevoiceImport::Importer.new(@data, user: @user, workspace: @workspace).run

    assert_equal 3, result.time_entries
    assert_equal 1, result.invoices
    assert_equal 3, result.linked_lines
    invoice = @workspace.invoices.order(:id).last
    assert_equal 3, invoice.invoice_lines.where.not(time_entry_id: nil).count
    assert @workspace.clients.exists?(name: "Acme Co")
    assert_equal 1350, @workspace.reload.invoice_setting.billable_rate_cents
  end

  test "keeps an existing billable rate" do
    rate = @workspace.invoice_setting.billable_rate_cents
    TimevoiceImport::Importer.new(@data, user: @user, workspace: @workspace).run
    assert_equal rate, @workspace.reload.invoice_setting.billable_rate_cents
  end

  test "running it twice adds nothing" do
    TimevoiceImport::Importer.new(@data, user: @user, workspace: @workspace).run
    again = TimevoiceImport::Importer.new(@data, user: @user, workspace: @workspace).run

    assert_equal [ 0, 0, 0, 0, 0 ], [ again.clients, again.projects, again.tags, again.time_entries, again.invoices ]
  end
end
