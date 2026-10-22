class AddActivitySourcesToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :github_repos, :text
    add_column :projects, :hackatime_projects, :text
    add_column :projects, :hackatime_catchall_projects, :text
    add_column :projects, :cloudflare_workers, :text
  end
end
