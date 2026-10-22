module Activity
  class Sync
    class SkipSource < StandardError; end

    SOURCES = [ GithubSync, HackatimeSync, CloudflareSync, VercelSync ].freeze

    Result = Struct.new(:imported, :skipped, :errors, keyword_init: true)

    def self.for_workspace(workspace, user:, from:, to:)
      results = workspace.projects.select(&:activity_sources?).map { |project| new(project: project, user: user, from: from, to: to).run }
      Result.new(
        imported: results.sum(&:imported),
        skipped: results.flat_map(&:skipped).uniq,
        errors: results.flat_map(&:errors)
      )
    end

    def initialize(project:, user:, from:, to:)
      @project = project
      @user = user
      @from = from
      @to = to
    end

    def run
      result = Result.new(imported: 0, skipped: [], errors: [])
      SOURCES.each do |source|
        result.imported += source.new(project: @project, user: @user, from: @from, to: @to).run
      rescue SkipSource => e
        result.skipped << e.message
      rescue HttpJson::Error, JSON::ParserError, SocketError, Timeout::Error, Errno::ECONNREFUSED => e
        result.errors << "#{@project.name}: #{e.message}"
      end
      @project.update_columns(activity_synced_at: Time.current, activity_sync_error: result.errors.join("\n").presence)
      result
    end
  end
end
