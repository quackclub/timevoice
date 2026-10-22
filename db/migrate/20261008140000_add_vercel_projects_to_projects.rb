class AddVercelProjectsToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :vercel_projects, :text
  end
end
