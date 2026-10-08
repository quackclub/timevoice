class SyncActivityJob < ApplicationJob
  queue_as :default

  def perform(workspace_id:, user_id:, from:, to:)
    workspace = Workspace.find(workspace_id)
    user = User.find(user_id)
    Activity::Sync.for_workspace(workspace, user: user, from: Time.zone.parse(from), to: Time.zone.parse(to))
  end
end
