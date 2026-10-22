module Activity
  class Recorder
    attr_reader :count

    def initialize(project:, user:, source:)
      @project = project
      @user = user
      @source = source
      @count = 0
    end

    def record(kind:, external_id:, occurred_at:, **attrs)
      event = @project.activity_events.find_or_initialize_by(kind: kind, external_id: external_id)
      event.assign_attributes(
        workspace_id: @project.workspace_id,
        user: @user,
        source: @source,
        occurred_at: occurred_at,
        **attrs
      )
      event.save!
      @count += 1
      event
    end
  end
end
