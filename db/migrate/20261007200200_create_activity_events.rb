class CreateActivityEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :activity_events do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :source, null: false
      t.string :external_id, null: false
      t.datetime :occurred_at, null: false
      t.datetime :ended_at
      t.integer :duration_seconds
      t.string :title
      t.string :url
      t.string :ref
      t.json :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :activity_events, [ :project_id, :kind, :external_id ], unique: true
    add_index :activity_events, [ :workspace_id, :occurred_at ]
  end
end
