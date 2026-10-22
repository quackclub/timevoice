class AddSenderEmailAndClientManager < ActiveRecord::Migration[8.1]
  def change
    add_column :invoice_settings, :sender_email, :string
    add_column :clients, :manager, :string
  end
end
