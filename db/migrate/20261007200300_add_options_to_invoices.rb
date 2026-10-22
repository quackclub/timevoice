class AddOptionsToInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :options, :json, null: false, default: {}
  end
end
