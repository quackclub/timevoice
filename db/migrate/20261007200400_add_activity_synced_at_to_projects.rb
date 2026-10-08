class AddActivitySyncedAtToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :activity_synced_at, :datetime
    add_column :projects, :activity_sync_error, :text
  end
end
