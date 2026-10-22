module Activity
  # Turns Hackatime heartbeats into coding blocks for one project.
  #
  # Heartbeats under the project's Hackatime project names always count.
  # Heartbeats under a catch-all project (e.g. "projects", a parent folder) count only when the
  # file path runs through a folder named after one of the project's repos and that file exists
  # in the repo on GitHub.
  #
  # Auth, in order: the user's Hackatime OAuth connection (read scope), the server's
  # HACKATIME_API_KEY when HACKATIME_API_KEY_EMAIL matches the user, then public spans
  # (no file names, so catch-all matching is skipped).
  class HackatimeSync
    BASE = "https://hackatime.hackclub.com".freeze
    BLOCK_GAP = 15.minutes.to_i
    HEARTBEAT_TIMEOUT = 2.minutes.to_i
    MIN_BLOCK = 60

    def initialize(project:, user:, from:, to:)
      @project = project
      @user = user
      @from = from
      @to = to
    end

    def run
      names = @project.hackatime_projects_list
      catchall = @project.hackatime_catchall_projects_list
      return 0 if names.empty? && catchall.empty?

      heartbeats = if (token = api_token)
        fetch_heartbeats(token, names, catchall)
      elsif (username = public_username)
        fetch_spans(username, names)
      else
        raise Activity::Sync::SkipSource, "connect Hackatime to import coding time"
      end

      recorder = Recorder.new(project: @project, user: @user, source: "hackatime")
      @project.activity_events.where(kind: "coding", source: "hackatime", user: @user).between(@from, @to).delete_all
      build_blocks(heartbeats).each do |block|
        next if block[:secs] < MIN_BLOCK
        recorder.record(kind: "coding", external_id: "coding:#{@user.id}:#{block[:start].to_i}",
          occurred_at: Time.zone.at(block[:start]), ended_at: Time.zone.at(block[:end]),
          duration_seconds: block[:secs].round, title: "Coding",
          metadata: { heartbeats: block[:count], via_catchall: block[:via], top_files: block[:files].sort_by { -_2 }.first(3).map(&:first) })
      end
      recorder.count
    end

    private

    def api_token
      oauth = @user.identity_for(:hackatime)&.access_token
      return oauth if oauth.present?
      key = ENV["HACKATIME_API_KEY"]
      key if key.present? && ENV["HACKATIME_API_KEY_EMAIL"].to_s.casecmp?(@user.email)
    end

    def public_username
      @user.identity_for(:hackatime)&.uid.presence || @user.github_login
    end

    def fetch_heartbeats(token, names, catchall)
      http = HttpJson.new(BASE, "Authorization" => "Bearer #{token}")
      out = []
      day = @from
      while day < @to
        chunk_end = [ day + 1.day, @to ].min
        data, = http.get("/api/v1/my/heartbeats", start_time: day.utc.iso8601, end_time: chunk_end.utc.iso8601)
        Array(data && data["heartbeats"]).each do |hb|
          if names.include?(hb["project"])
            out << { t: hb["time"].to_f, file: hb["entity"].to_s, via: false }
          elsif catchall.include?(hb["project"]) && (rel = catchall_match(hb["entity"].to_s))
            out << { t: hb["time"].to_f, file: rel, via: true }
          end
        end
        day = chunk_end
      end
      out
    end

    def fetch_spans(username, names)
      http = HttpJson.new(BASE)
      names.flat_map do |name|
        begin
          data, = http.get("/api/v1/users/#{ERB::Util.url_encode(username)}/heartbeats/spans",
            project: name, start_date: @from.utc.iso8601, end_date: @to.utc.iso8601)
        rescue HttpJson::Error => e
          raise Activity::Sync::SkipSource, "Hackatime has no public stats for #{username}; connect Hackatime to import coding time" if e.message.match?(/ 40[34]:/)
          raise
        end
        Array(data && data["spans"]).map do |span|
          { start: span["start_time"].to_f, end: span["end_time"].to_f, secs: span["duration"].to_f, file: "", via: false }
        end
      end
    end

    def repo_dirs
      @repo_dirs ||= (@project.github_repos_list.map { |r| r.split("/").last } + @project.hackatime_projects_list).uniq
    end

    def catchall_match(entity)
      dirs = repo_dirs.map { |d| Regexp.escape(d) }.join("|")
      return nil if dirs.empty?
      m = entity.match(%r{/(#{dirs})/(?:\.herdr/worktrees/[^/]+/)?(.+)\z})
      return nil unless m
      rel = m[2]
      rel if repo_files.include?(rel)
    end

    def repo_files
      @repo_files ||= begin
        token = ENV["GITHUB_TOKEN"].presence || @user.identity_for(:github)&.access_token
        headers = { "Accept" => "application/vnd.github+json", "User-Agent" => "timevoice" }
        headers["Authorization"] = "Bearer #{token}" if token
        http = HttpJson.new("https://api.github.com", headers)
        @project.github_repos_list.each_with_object(Set.new) do |repo, set|
          info, = http.get("/repos/#{repo}")
          tree, = http.get("/repos/#{repo}/git/trees/#{info['default_branch']}", recursive: 1)
          tree["tree"].each { |node| set << node["path"] if node["type"] == "blob" }
        rescue HttpJson::Error
          next
        end
      end
    end

    # Heartbeats are points; spans (public fallback) are intervals that already carry their duration.
    def build_blocks(items)
      blocks = []
      items.map { |i| i[:start] ? i : i.merge(start: i[:t], end: i[:t], secs: 0) }.sort_by { _1[:start] }.each do |item|
        cur = blocks.last
        if cur && item[:start] - cur[:end] <= BLOCK_GAP
          gap = item[:start] - cur[:end]
          cur[:secs] += item[:secs].zero? ? [ gap, HEARTBEAT_TIMEOUT ].min.clamp(0, nil) : item[:secs]
          cur[:end] = [ cur[:end], item[:end] ].max
        else
          cur = { start: item[:start], end: item[:end], secs: item[:secs], count: 0, via: 0, files: Hash.new(0) }
          blocks << cur
        end
        cur[:count] += 1
        cur[:via] += 1 if item[:via]
        name = item[:file].to_s.split("/").last.to_s
        cur[:files][name] += 1 if name.include?(".")
      end
      blocks
    end
  end
end
