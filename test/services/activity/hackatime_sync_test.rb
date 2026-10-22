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

class Activity::VercelSyncTest < ActiveSupport::TestCase
  setup do
    @project = projects(:one)
    @project.update_columns(vercel_projects: "slacker-news")
    @user = users(:one)
    @user.identities.create!(provider: "github", uid: "9", username: "matmanna")
  end

  def deployment(uid, login, created)
    { "uid" => uid, "name" => "slacker-news", "url" => "#{uid}.vercel.app", "created" => (created.to_f * 1000).to_i,
      "target" => "production", "state" => "READY",
      "meta" => { "githubCommitAuthorLogin" => login, "githubCommitRef" => "main", "githubCommitSha" => "abcdef1234" } }
  end

  test "imports only the user's deploys as deploy receipts" do
    with_env("VERCEL_TOKEN" => "t") do
      sync = Activity::VercelSync.new(project: @project, user: @user, from: 2.days.ago, to: Time.current)
      http = Object.new
      deploys = [ deployment("dpl_mine", "matmanna", 1.hour.ago), deployment("dpl_other", "someone", 2.hours.ago) ]
      http.define_singleton_method(:get) { |*| [ { "deployments" => deploys, "pagination" => {} }, nil ] }
      Activity::HttpJson.define_singleton_method(:new) { |*| http }
      begin
        assert_equal 1, sync.run
      ensure
        Activity::HttpJson.singleton_class.remove_method(:new)
      end
    end

    event = @project.activity_events.sole
    assert_equal "deploy", event.kind
    assert_equal "vercel", event.metadata["provider"]
    assert_equal "abcdef1", event.metadata["commit_sha"]
  end

  test "skips with advice when VERCEL_TOKEN is missing" do
    with_env("VERCEL_TOKEN" => nil) do
      sync = Activity::VercelSync.new(project: @project, user: @user, from: 1.day.ago, to: Time.current)
      assert_raises(Activity::Sync::SkipSource) { sync.run }
    end
  end

  def with_env(vars)
    old = vars.keys.to_h { |k| [ k, ENV[k] ] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end
end
