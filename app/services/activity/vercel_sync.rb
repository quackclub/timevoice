module Activity
  # Imports Vercel deployments for the project's Vercel projects.
  # Uses the server's VERCEL_TOKEN (plus VERCEL_TEAM_ID for team-owned projects).
  # Only deployments the user made or whose commit the user authored are kept.
  class VercelSync
    PAGE_LIMIT = 100
    MAX_PAGES = 20

    def initialize(project:, user:, from:, to:)
      @project = project
      @user = user
      @from = from
      @to = to
    end

    def run
      names = @project.vercel_projects_list
      return 0 if names.empty?
      token = ENV["VERCEL_TOKEN"]
      raise Activity::Sync::SkipSource, "set VERCEL_TOKEN (and VERCEL_TEAM_ID for team projects) to import Vercel deploys" if token.blank?

      http = HttpJson.new("https://api.vercel.com", "Authorization" => "Bearer #{token}")
      recorder = Recorder.new(project: @project, user: @user, source: "vercel")
      names.each do |name|
        each_deployment(http, name) do |d|
          next unless mine?(d)
          at = Time.zone.at(d["created"] / 1000.0)
          meta = d["meta"] || {}
          target = d["target"].presence || "preview"
          recorder.record(kind: "deploy", external_id: d["uid"], occurred_at: at,
            title: "Deploy #{d['name'] || name} (#{target})", ref: d["uid"].to_s.delete_prefix("dpl_"),
            url: d["inspectorUrl"].presence || "https://#{d['url']}",
            metadata: { provider: "vercel", project: d["name"] || name, target: target, state: d["state"] || d["readyState"],
                        branch: meta["githubCommitRef"], commit_sha: meta["githubCommitSha"]&.slice(0, 7),
                        commit_message: meta["githubCommitMessage"]&.lines&.first&.strip })
        end
      end
      recorder.count
    end

    private

    def each_deployment(http, name)
      query = { app: name, since: (@from.to_f * 1000).to_i, until: (@to.to_f * 1000).to_i, limit: PAGE_LIMIT, teamId: ENV["VERCEL_TEAM_ID"].presence }
      MAX_PAGES.times do
        data, = http.get("/v6/deployments", query)
        Array(data["deployments"]).each { |d| yield d }
        nxt = data.dig("pagination", "next")
        break if nxt.blank? || Array(data["deployments"]).size < PAGE_LIMIT
        query[:until] = nxt
      end
    end

    # Deploys carry the GitHub login of whoever triggered them or authored the commit.
    # CLI deploys without GitHub info are kept: they come from the token owner's account.
    def mine?(deployment)
      login = @user.github_login
      return true if login.blank?
      logins = [ deployment.dig("creator", "githubLogin"), deployment.dig("meta", "githubCommitAuthorLogin") ].compact
      logins.empty? || logins.any? { |l| l.casecmp?(login) }
    end
  end
end
