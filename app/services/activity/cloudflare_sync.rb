module Activity
  # Imports Cloudflare Worker version uploads (one per `wrangler deploy`) for the project's workers.
  # Uses the server's CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID. The versions API keeps far
  # more history than `wrangler deployments list`, which only returns the latest 10.
  class CloudflareSync
    def initialize(project:, user:, from:, to:)
      @project = project
      @user = user
      @from = from
      @to = to
    end

    def run
      workers = @project.cloudflare_workers_list
      return 0 if workers.empty?
      token = ENV["CLOUDFLARE_API_TOKEN"]
      account = ENV["CLOUDFLARE_ACCOUNT_ID"]
      raise Activity::Sync::SkipSource, "set CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID to import deploys" if token.blank? || account.blank?

      http = HttpJson.new("https://api.cloudflare.com", "Authorization" => "Bearer #{token}")
      recorder = Recorder.new(project: @project, user: @user, source: "cloudflare")
      workers.each do |worker|
        page = 1
        loop do
          data, = http.get("/client/v4/accounts/#{account}/workers/scripts/#{ERB::Util.url_encode(worker)}/versions", per_page: 100, page: page)
          items = Array(data.dig("result", "items"))
          items.each do |v|
            at = Time.zone.parse(v.dig("metadata", "created_on"))
            next unless at >= @from && at <= @to
            recorder.record(kind: "deploy", external_id: v["id"], occurred_at: at,
              title: "Deploy #{worker}", ref: v["id"],
              url: "https://dash.cloudflare.com/#{account}/workers/services/view/#{worker}/production/deployments",
              metadata: { provider: "cloudflare", worker: worker, source: v.dig("metadata", "source"), author_email: v.dig("metadata", "author_email"),
                          message: v.dig("annotations", "workers/message") })
          end
          break if items.size < 100 || page >= 10
          page += 1
        end
      end
      recorder.count
    end
  end
end
