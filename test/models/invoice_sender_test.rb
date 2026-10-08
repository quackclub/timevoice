require "test_helper"

class InvoiceSenderTest < ActiveSupport::TestCase
  setup do
    @invoice = invoices(:one)
    @workspace = @invoice.workspace
  end

  test "sender falls back to the workspace owner's name and email" do
    @workspace.invoice_setting&.destroy
    sender = @invoice.reload.sender
    assert_equal @workspace.owner.name, sender[:name]
    assert_equal @workspace.owner.email, sender[:email]
  end

  test "billing settings override the From name and email, and the PDF still renders with a client manager" do
    setting = @workspace.invoice_setting || @workspace.build_invoice_setting
    setting.update!(sender_name: "Mat Manna", sender_email: "invoices@example.com", sender_address: "1 Main St")
    @invoice.client.update_columns(manager: "Jane Doe")

    assert_equal({ name: "Mat Manna", email: "invoices@example.com", address: "1 Main St" }, @invoice.reload.sender)
    assert InvoicePdf.new(@invoice, setting).generate.start_with?("%PDF")
  end
end
