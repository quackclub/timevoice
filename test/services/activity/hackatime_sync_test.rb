require "test_helper"

class Activity::HackatimeSyncTest < ActiveSupport::TestCase
  setup do
    @project = projects(:one)
    @project.update_columns(github_repos: "hackclub/slacker-news", hackatime_projects: "slacker-news", hackatime_catchall_projects: "projects")
    @sync = Activity::HackatimeSync.new(project: @project, user: users(:one), from: 1.day.ago, to: Time.current)
    @sync.instance_variable_set(:@repo_files, Set["src/pages/index.astro", "src/components/SlackRichText.astro"])
  end

  test "catch-all heartbeats match only files that exist in the repo" do
    assert_equal "src/pages/index.astro", @sync.send(:catchall_match, "/home/me/projects/slacker-news/src/pages/index.astro")
    assert_nil @sync.send(:catchall_match, "/home/me/projects/slacker-news/node_modules/x.js")
    assert_nil @sync.send(:catchall_match, "/home/me/projects/other/src/pages/index.astro")
  end

  test "worktree paths are matched with the worktree prefix removed" do
    assert_equal "src/components/SlackRichText.astro",
      @sync.send(:catchall_match, "/home/me/projects/slacker-news/.herdr/worktrees/slacker-news/src/components/SlackRichText.astro")
  end

  test "blocks split after 15 idle minutes and cap each gap at 2 minutes" do
    hbs = [ 0, 60, 600, 600 + 16 * 60 ].map { |t| { t: t.to_f, file: "a.rb", via: false } }
    blocks = @sync.send(:build_blocks, hbs)
    assert_equal 2, blocks.size
    assert_equal 60 + 120, blocks.first[:secs]
  end
end

class Activity::GithubSyncTest < ActiveSupport::TestCase
  test "a rejected GitHub token becomes a skip with reconnect advice" do
    project = projects(:one)
    project.update_columns(github_repos: "hackclub/slacker-news")
    user = users(:one)
    user.identities.create!(provider: "github", uid: "1", username: "someone", access_token: "expired")
    sync = Activity::GithubSync.new(project: project, user: user, from: 1.day.ago, to: Time.current)
    http = Object.new
    def http.get(*) = raise(Activity::HttpJson::Error, "api.github.com/repos/x returned 401: Bad credentials")
    sync.instance_variable_set(:@http, http)

    error = assert_raises(Activity::Sync::SkipSource) { sync.run }
    assert_match "reconnect GitHub", error.message
  end
end
