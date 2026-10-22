module TimevoiceImport
  # Copies an export from another Timevoice instance into a workspace. Safe to run again:
  # clients, projects and tags match by name, time entries by start time, invoices by
  # client + period + total.
  class Importer
    Result = Struct.new(:clients, :projects, :tags, :time_entries, :invoices, :linked_lines, keyword_init: true)

    def initialize(data, user:, workspace:)
      @data = data
      @user = user
      @workspace = workspace
    end

    def run
      result = Result.new(clients: 0, projects: 0, tags: 0, time_entries: 0, invoices: 0, linked_lines: 0)
      ActiveRecord::Base.transaction do
        clients = import_clients(result)
        projects = import_projects(clients, result)
        tags = import_tags(result)
        entries = import_entries(projects, tags, result)
        import_rate
        import_invoices(clients, entries, result)
      end
      result
    end

    private

    def import_clients(result)
      Array(@data["clients"]).to_h do |c|
        client = @workspace.clients.find_or_initialize_by(name: c["name"])
        result.clients += 1 if client.new_record?
        client.billing_address = c["billing_address"] if client.billing_address.blank?
        client.save!
        [ c["id"], client ]
      end
    end

    def import_projects(clients, result)
      Array(@data["projects"]).to_h do |p|
        project = @workspace.projects.find_or_initialize_by(name: p["name"])
        if project.new_record?
          result.projects += 1
          project.assign_attributes(color: p["color"].presence || Project.default_color, billable_default: p["billable_default"],
            client: clients[p.dig("client", "id")])
          project.save!
        end
        [ p["id"], project ]
      end
    end

    def import_tags(result)
      Array(@data["tags"]).to_h do |t|
        tag = @workspace.tags.find_or_initialize_by(name: t["name"])
        result.tags += 1 if tag.new_record?
        tag.save!
        [ t["id"], tag ]
      end
    end

    def import_entries(projects, tags, result)
      Array(@data["time_entries"]).filter_map do |t|
        next if t["end_at"].blank? # skip timers still running on the old instance
        start_at = Time.zone.parse(t["start_at"])
        entry = @workspace.time_entries.find_by(user: @user, start_at: start_at)
        unless entry
          entry = @workspace.time_entries.create!(user: @user, start_at: start_at, end_at: Time.zone.parse(t["end_at"]),
            description: t["description"].presence || "Imported entry", billable: t["billable"], project: projects[t.dig("project", "id")])
          entry.tags = Array(t["tags"]).filter_map { |tg| tags[tg["id"]] }
          result.time_entries += 1
        end
        entry
      end
    end

    def import_rate
      rate = Array(@data["invoices"]).flat_map { Array(_1["invoice_lines"]) }.first&.dig("rate_cents")
      setting = InvoiceSetting.find_or_initialize_by(workspace: @workspace)
      setting.sender_name = @user.name if setting.sender_name.blank?
      setting.billable_rate_cents = rate if rate && setting.billable_rate_cents.to_i.zero?
      setting.save! if setting.changed?
    end

    def import_invoices(clients, entries, result)
      Array(@data["invoices"]).each do |inv|
        client = clients[inv.dig("client", "id")]
        next unless client
        attrs = { client: client, period_start: inv["period_start"], period_end: inv["period_end"], total_cents: inv["total_cents"] }
        next if @workspace.invoices.exists?(attrs)

        invoice = @workspace.invoices.create!(attrs.merge(issued_on: inv["issued_on"] || Date.current, status: inv["status"] || "draft"))
        pool = entries.dup
        Array(inv["invoice_lines"]).each do |l|
          match = pool.find { |e| e.description == l["description"] && (e.duration_hours.round(2) - l["qty_hours"].to_f).abs < 0.011 } ||
                  pool.find { |e| e.description == l["description"] }
          pool.delete(match)
          result.linked_lines += 1 if match
          invoice.invoice_lines.create!(description: l["description"], qty_hours: l["qty_hours"], rate_cents: l["rate_cents"],
            amount_cents: l["amount_cents"], time_entry: match)
        end
        result.invoices += 1
      end
    end
  end
end
