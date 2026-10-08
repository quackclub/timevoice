module Activity
  # Imports GitHub activity for one user into one project:
  # PRs opened, commits inside those PRs, commits on the default branch,
  # squash-merges, PRs by others that the user merged, and branch creations.
  class GithubSync
    def initialize(project:, user:, from:, to:)
      @project = project
      @user = user
      @from = from
      @to = to
      @login = user.github_login
      token = ENV["GITHUB_TOKEN"].presence || user.identity_for(:github)&.access_token
      headers = { "Accept" => "application/vnd.github+json", "X-GitHub-Api-Version" => "2022-11-28", "User-Agent" => "timevoice" }
      headers["Authorization"] = "Bearer #{token}" if token
      @http = HttpJson.new("https://api.github.com", headers)
    end

    def run
      raise Activity::Sync::SkipSource, "connect GitHub (or Hackatime with a GitHub username) to import GitHub activity" if @login.blank?

      count = 0
      @project.github_repos_list.each do |repo|
        count += sync_repo(repo)
      end
      count
    rescue HttpJson::Error => e
      raise unless e.message.include?(" returned 401:")
      raise Activity::Sync::SkipSource, "GitHub rejected the saved sign-in token; reconnect GitHub in Settings → Integrations (or set GITHUB_TOKEN on the server)"
    end

    private

    def sync_repo(repo)
      info, = @http.get("/repos/#{repo}")
      default_branch = info["default_branch"]
      @recorder = Recorder.new(project: @project, user: @user, source: "github")

      pr_commit_shas = sync_pull_requests(repo)
      sync_default_branch(repo, default_branch, pr_commit_shas)
      sync_reviewed(repo)
      sync_branches(repo)
      @recorder.count
    end

    def in_range?(time)
      time && time >= @from && time <= @to
    end

    def search(q)
      items = []
      page = 1
      loop do
        data, = @http.get("/search/issues", q: q, per_page: 100, page: page)
        items.concat(data["items"])
        break if data["items"].size < 100 || items.size >= data["total_count"] || page >= 10
        page += 1
      end
      items
    end

    def paginate(path, query = {})
      results = []
      data, res = @http.get(path, query.merge(per_page: 100))
      results.concat(data)
      while (link = res["link"]) && (nxt = link[/<([^>]+)>;\s*rel="next"/, 1])
        data, res = @http.get_url(nxt)
        results.concat(data)
      end
      results
    end

    def sync_pull_requests(repo)
      shas = {}
      prs = search("repo:#{repo} is:pr author:#{@login} updated:>=#{@from.to_date.iso8601}")
      prs.each do |pr|
        number = pr["number"]
        created = Time.zone.parse(pr["created_at"])
        if in_range?(created)
          state = pr.dig("pull_request", "merged_at") ? "merged" : pr["state"]
          @recorder.record(kind: "pr", external_id: "#{repo}##{number}", occurred_at: created,
            title: pr["title"], url: pr["html_url"], ref: "##{number}",
            metadata: { repo: repo, number: number, state: state })
        end

        paginate("/repos/#{repo}/pulls/#{number}/commits").each do |c|
          next unless c.dig("author", "login") == @login
          at = Time.zone.parse(c.dig("commit", "author", "date"))
          next unless in_range?(at)
          (shas[c["sha"]] ||= { commit: c, at: at, prs: [] })[:prs] << number
        end
      end

      shas.each do |sha, entry|
        message = entry[:commit].dig("commit", "message").to_s.lines.first.to_s.strip
        @recorder.record(kind: "commit", external_id: sha, occurred_at: entry[:at], title: message,
          url: "https://github.com/#{repo}/commit/#{sha}", ref: sha,
          metadata: { repo: repo, prs: entry[:prs].uniq.sort, merge_branch: message.start_with?("Merge ") }.merge(stats(repo, sha)))
      end
      shas.keys.to_set
    end

    def sync_default_branch(repo, branch, pr_shas)
      paginate("/repos/#{repo}/commits", sha: branch, author: @login, since: @from.utc.iso8601, until: @to.utc.iso8601).each do |c|
        next if pr_shas.include?(c["sha"])
        at = Time.zone.parse(c.dig("commit", "author", "date"))
        next unless in_range?(at)
        message = c.dig("commit", "message").to_s.lines.first.to_s.strip
        pr_number = message[/\(#(\d+)\)\z/, 1]&.to_i
        @recorder.record(kind: pr_number ? "merge" : "main", external_id: c["sha"], occurred_at: at,
          title: message.sub(/\s*\(#\d+\)\z/, ""), url: c["html_url"], ref: c["sha"],
          metadata: { repo: repo, prs: [ pr_number ].compact, merge_branch: message.start_with?("Merge ") }.merge(stats(repo, c["sha"])))
      end
    end

    def sync_reviewed(repo)
      search("repo:#{repo} is:pr is:merged -author:#{@login} merged:#{@from.to_date.iso8601}..#{@to.to_date.iso8601}").each do |pr|
        full, = @http.get("/repos/#{repo}/pulls/#{pr['number']}")
        next unless full.dig("merged_by", "login") == @login
        at = Time.zone.parse(full["merged_at"])
        next unless in_range?(at)
        @recorder.record(kind: "reviewed", external_id: "#{repo}##{pr['number']}", occurred_at: at,
          title: pr["title"], url: pr["html_url"], ref: "##{pr['number']}",
          metadata: { repo: repo, number: pr["number"], opened_by: pr.dig("user", "login") })
      end
    end

    # The events API only reaches back 90 days (300 events), so older branches are not available.
    def sync_branches(repo)
      seen = {}
      events = begin
        paginate("/repos/#{repo}/events")
      rescue HttpJson::Error
        []
      end
      events.each do |ev|
        next unless ev["type"] == "CreateEvent" && ev.dig("payload", "ref_type") == "branch" && ev.dig("actor", "login") == @login
        at = Time.zone.parse(ev["created_at"])
        next unless in_range?(at)
        ref = ev.dig("payload", "ref")
        key = "#{repo}:#{ref}:#{at.in_time_zone(@user.timezone.presence || 'UTC').to_date}"
        if seen[key]
          seen[key][:times] += 1
          seen[key][:at] = [ seen[key][:at], at ].min
        else
          seen[key] = { ref: ref, at: at, times: 1 }
        end
      end
      seen.each do |key, b|
        @recorder.record(kind: "branch", external_id: key, occurred_at: b[:at], title: b[:ref],
          url: "https://github.com/#{repo}/tree/#{b[:ref]}", ref: b[:ref],
          metadata: { repo: repo, times: b[:times] })
      end
    end

    def stats(repo, sha)
      existing = @project.activity_events.find_by(external_id: sha)&.metadata
      return existing.slice("additions", "deletions", "files") if existing&.key?("additions")
      data, = @http.get("/repos/#{repo}/commits/#{sha}")
      { additions: data.dig("stats", "additions"), deletions: data.dig("stats", "deletions"), files: data["files"]&.size }
    rescue HttpJson::Error
      {}
    end
  end
end
