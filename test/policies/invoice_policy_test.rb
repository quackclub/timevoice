require "test_helper"

class InvoicePolicyTest < ActiveSupport::TestCase
  test "every action the controller authorizes has a policy method" do
    actions = InvoicesController._process_action_callbacks
      .select { |cb| cb.filter == :authorize_invoice }
      .flat_map { |cb| cb.instance_variable_get(:@if).flat_map { |c| c.instance_variable_get(:@actions).to_a } }

    assert_includes actions, "refresh_activity"
    actions.each { |action| assert InvoicePolicy.method_defined?("#{action}?"), "InvoicePolicy is missing #{action}?" }
  end
end
