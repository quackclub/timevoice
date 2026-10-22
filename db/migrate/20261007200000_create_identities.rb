class CreateIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :identities do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :uid, null: false
      t.string :username
      t.string :email
      t.text :access_token
      t.text :refresh_token
      t.datetime :expires_at
      t.string :scopes
      t.timestamps
    end
    add_index :identities, [ :provider, :uid ], unique: true
    add_index :identities, [ :user_id, :provider ], unique: true

    change_column_null :users, :google_uid, true

    reversible do |dir|
      dir.up do
        execute <<~SQL
          INSERT INTO identities (user_id, provider, uid, email, created_at, updated_at)
          SELECT id, 'google_oauth2', google_uid, email, created_at, updated_at FROM users WHERE google_uid IS NOT NULL
        SQL
      end
    end
  end
end
