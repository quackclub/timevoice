require "prawn"
require "prawn/table"

class InvoicePdf
  BRAND_COLOR = "6366F1"
  TEXT_PRIMARY = "1A1A1A"
  TEXT_SECONDARY = "666666"
  TEXT_MUTED = "999999"
  BORDER_COLOR = "EEEEEE"

  # reconciliation: nil follows the invoice's own option; true/false overrides it for this export.
  def initialize(invoice, invoice_setting, reconciliation: nil)
    @invoice = invoice
    @invoice_setting = invoice_setting
    @reconciliation = reconciliation.nil? ? @invoice.settings["reconciliation"] : reconciliation
    @document = Prawn::Document.new(
      page_size: "A4",
      margin: [ 60, 60, 60, 60 ]
    )
    setup_fonts
  end

  def generate
    build_header
    build_invoice_meta
    build_addresses
    if @invoice.detailed?
      build_timeline
    else
      build_line_items_table
    end
    build_totals_section
    build_reconciliation if @invoice.detailed? && @reconciliation

    @document.render
  end

  private

  def setup_fonts
    font_path = Rails.root.join("app", "assets", "fonts")

    @document.font_families.update(
      "PublicSans" => {
        normal: File.join(font_path, "PublicSans-Regular.ttf"),
        bold: File.join(font_path, "PublicSans-Bold.ttf")
      }
    )

    @document.font "PublicSans"
  end

  def build_header
    sender_name = @invoice.sender[:name] || "Your Company"

    @document.text "INVOICE",
      size: 11,
      color: TEXT_SECONDARY,
      character_spacing: 1.5

    @document.move_down 6

    @document.text sender_name,
      size: 28,
      style: :bold,
      color: TEXT_PRIMARY

    @document.move_down 20
  end

  def build_invoice_meta
    col_width = @document.bounds.width / 3

    @document.bounding_box([ 0, @document.cursor ], width: @document.bounds.width, height: 35) do
      [ [ "Invoice #", invoice_number, 0 ],
        [ "Issue Date", format_date(@invoice.issued_on), col_width ],
        [ "Period", "#{format_date(@invoice.period_start)} – #{format_date(@invoice.period_end)}", col_width * 2 ]
      ].each do |label, value, x_pos|
        @document.bounding_box([ x_pos, @document.bounds.top ], width: col_width) do
          @document.text label, size: 9, color: TEXT_SECONDARY
          @document.move_down 2
          @document.text value, size: 10, color: TEXT_PRIMARY, style: :bold
        end
      end
    end

    @document.move_down 20
  end

  def build_addresses
    start_y = @document.cursor
    col_width = (@document.bounds.width / 2) - 15

    @document.bounding_box([ 0, start_y ], width: col_width) do
      @document.text "From",
        size: 10,
        color: TEXT_SECONDARY

      @document.move_down 8

      sender = @invoice.sender
      @document.text sender[:name] || "Your Company",
        size: 12,
        style: :bold,
        color: TEXT_PRIMARY

      @document.move_down 6

      if sender[:email].present?
        @document.text sender[:email], size: 9, color: TEXT_SECONDARY
        @document.move_down 4
      end

      if sender[:address].present?
        @document.text sender[:address],
          size: 9,
          color: TEXT_SECONDARY,
          leading: 4
      end
    end

    @document.bounding_box([ col_width + 30, start_y ], width: col_width) do
      @document.text "Bill To",
        size: 10,
        color: TEXT_SECONDARY

      @document.move_down 8

      @document.text @invoice.client.name,
        size: 12,
        style: :bold,
        color: TEXT_PRIMARY

      @document.move_down 6

      if @invoice.client.manager.present?
        @document.text "Attn: #{@invoice.client.manager}", size: 9, color: TEXT_SECONDARY
        @document.move_down 4
      end

      if @invoice.client.billing_address.present?
        @document.text @invoice.client.billing_address,
          size: 9,
          color: TEXT_SECONDARY,
          leading: 4
      end
    end

    @document.move_cursor_to(start_y - 115)
  end

  def build_line_items_table
    @document.move_down 35

    @document.stroke_color BORDER_COLOR
    @document.stroke_horizontal_rule
    @document.move_down 25

    @document.text "Line Items",
      size: 14,
      style: :bold,
      color: TEXT_PRIMARY

    @document.move_down 15

    table_data = [ [ "Description", "Rate", "Hours", "Amount" ] ]

    @invoice.invoice_lines.each do |line|
      hours = line.qty_hours || 0
      description = sanitize_text(line.description) || "No description"

      table_data << [
        description,
        format_currency(line.rate_cents),
        format("%.2f", hours),
        format_currency(line.amount_cents)
      ]
    end

    @document.table(table_data, width: @document.bounds.width) do |t|
      t.cells.border_width = 0
      t.cells.padding = [ 10, 0, 10, 0 ]

      t.row(0).font_style = :bold
      t.row(0).size = 10
      t.row(0).text_color = TEXT_SECONDARY
      t.row(0).border_bottom_width = 1
      t.row(0).border_bottom_color = BORDER_COLOR

      t.rows(1..-1).size = 10
      t.rows(1..-1).text_color = TEXT_PRIMARY
      t.rows(1..-1).border_bottom_width = 1
      t.rows(1..-1).border_bottom_color = "F5F5F5"

      t.columns(1..3).align = :right
      t.column(0).width = @document.bounds.width * 0.45
    end

    @document.move_down 25
  end

  def build_totals_section
    totals_width = 200

    totals_data = [
      [ "Subtotal", format_currency(@invoice.total_cents) ],
      [ "Total Due", "#{format_currency(@invoice.total_cents)} USD" ]
    ]

    @document.bounding_box([ @document.bounds.width - totals_width, @document.cursor ], width: totals_width) do
      @document.table(totals_data, width: totals_width) do |t|
        t.cells.border_width = 0
        t.cells.padding = [ 6, 0, 6, 0 ]
        t.cells.size = 10

        t.column(0).text_color = TEXT_SECONDARY
        t.column(1).text_color = TEXT_PRIMARY
        t.column(1).align = :right

        t.row(-1).font_style = :bold
        t.row(-1).size = 12
        t.row(-1).text_color = TEXT_PRIMARY
        t.row(-1).border_top_width = 1
        t.row(-1).border_top_color = BORDER_COLOR
        t.row(-1).padding_top = 10
      end
    end
  end

  KIND_LABELS = {
    "commit" => "COMMIT", "main" => "MAIN", "merge" => "MERGE", "pr" => "PR", "reviewed" => "MERGED",
    "branch" => "BRANCH", "deploy" => "DEPLOY", "coding" => "CODING"
  }.freeze
  KIND_COLORS = {
    "commit" => "33A36B", "main" => "A633D6", "merge" => "8C6B2A", "pr" => "338EDA", "reviewed" => "0E8A8A",
    "branch" => "5C6370", "deploy" => "F38020", "coding" => "D6336C"
  }.freeze

  def zone
    @zone ||= ActiveSupport::TimeZone[@invoice.time_zone] || Time.zone
  end

  def build_timeline
    @document.move_down 35
    @document.stroke_color BORDER_COLOR
    @document.stroke_horizontal_rule
    @document.move_down 25
    @document.text "Work Log", size: 14, style: :bold, color: TEXT_PRIMARY
    @document.text "Grouped by day (#{zone.name}). Receipts sit under the time entry they happened during.",
      size: 8, color: TEXT_MUTED
    @document.move_down 10

    @invoice.timeline_days.each do |day|
      @document.start_new_page if @document.cursor < 90
      @document.move_down 8
      @document.stroke_color BORDER_COLOR
      @document.stroke_horizontal_rule
      @document.move_down 8
      summary = day.entries.any? ? format_duration(day.billed_seconds) + " billed" : "no billed time"
      y = @document.cursor
      @document.text day.date.strftime("%a, %b %-d"), size: 11, style: :bold, color: day.entries.any? ? TEXT_PRIMARY : TEXT_MUTED
      @document.draw_text summary, at: [ @document.bounds.width - @document.width_of(summary, size: 8), y - 9 ], size: 8, color: TEXT_SECONDARY
      @document.move_down 4

      day.entries.each do |w|
        line = w.line
        row = [
          sanitize_text(line&.description || w.entry.description).to_s,
          format_duration(w.entry.duration.to_i),
          line ? format("%.2f h", line.qty_hours || 0) : "",
          line ? format_currency(line.rate_cents) : "",
          line ? format_currency(line.amount_cents) : ""
        ]
        @document.table([ row ], width: @document.bounds.width, column_widths: { 0 => @document.bounds.width * 0.52 }) do |t|
          t.cells.border_width = 0
          t.cells.padding = [ 4, 0, 2, 6 ]
          t.cells.size = 9.5
          t.column(0).font_style = :bold
          t.column(0).padding = [ 4, 0, 2, 0 ]
          t.columns(1..4).align = :right
          t.column(1).text_color = TEXT_SECONDARY
        end
        @document.text "#{w.entry.start_at.in_time_zone(zone).strftime('%-I:%M %p')} – #{(w.entry.end_at || w.entry.start_at).in_time_zone(zone).strftime('%-I:%M %p')}#{w.entry.project ? " · #{sanitize_text(w.entry.project.name)}" : ''}",
          size: 7.5, color: TEXT_MUTED
        receipts(w.events)
      end

      if day.events.any?
        @document.move_down 2
        @document.text(day.entries.any? ? "Other activity this day" : "Activity (not billed)", size: 7.5, color: TEXT_MUTED, style: :bold)
        receipts(day.events)
      end
    end
    @document.move_down 20
  end

  def receipts(events)
    return if events.empty?
    rows = events.map do |e|
      time = e.occurred_at.in_time_zone(zone).strftime("%-I:%M %p").downcase
      ref = e.kind == "coding" ? format_minutes(e.duration_seconds.to_i) : e.short_ref.to_s
      [ time, KIND_LABELS[e.kind], ref, receipt_text(e) ]
    end
    @document.indent(10) do
      @document.table(rows, width: @document.bounds.width, column_widths: { 0 => 46, 1 => 46, 2 => 50 }) do |t|
        t.cells.border_width = 0
        t.cells.padding = [ 1.5, 4, 1.5, 0 ]
        t.cells.size = 7.5
        t.column(0).text_color = TEXT_MUTED
        t.column(1).font_style = :bold
        t.column(1).size = 6.5
        events.each_with_index do |e, i|
          t.row(i).column(1).text_color = KIND_COLORS[e.kind]
          t.row(i).column(2).text_color = KIND_COLORS[e.kind]
        end
        t.column(3).text_color = TEXT_PRIMARY
      end
    end
    @document.move_down 4
  end

  def receipt_text(e)
    m = e.metadata || {}
    repo = m["repo"].to_s.split("/").last
    text = case e.kind
    when "pr" then "opened: #{e.title}"
    when "commit" then "#{e.title}  (#{repo} · in ##{Array(m['prs']).join(' #')})"
    when "merge" then "#{e.title}  (#{repo} · squash-merge of ##{Array(m['prs']).join(' #')})"
    when "main" then "#{e.title}  (#{repo} · direct to default branch)"
    when "reviewed" then "reviewed & merged: #{e.title}  (opened by @#{m['opened_by']})"
    when "branch" then "new branch #{e.title}  (#{m['repo']}#{m['times'].to_i > 1 ? " · ×#{m['times']}" : ''})"
    when "deploy"
      detail = m["provider"] == "vercel" ? [ m["branch"], m["commit_sha"], m["state"]&.downcase ].compact.join(" · ") : "version #{e.ref.to_s[0, 8]}"
      "#{e.title}  (#{detail})"
    when "coding" then "#{e.occurred_at.in_time_zone(zone).strftime('%-I:%M %p').downcase} – #{e.ended_at&.in_time_zone(zone)&.strftime('%-I:%M %p')&.downcase} · #{m['heartbeats']} heartbeats#{m['top_files'].present? ? " · #{Array(m['top_files']).join(', ')}" : ''}"
    else e.title
    end
    sanitize_text(text).to_s
  end

  def build_reconciliation
    est = @invoice.estimates
    @document.start_new_page
    @document.text "Time reconciliation", size: 14, style: :bold, color: TEXT_PRIMARY
    @document.text "Billed time compared with three independent estimates from the receipts above.", size: 9, color: TEXT_SECONDARY
    @document.move_down 12
    t = est[:totals]
    pct = ->(v) { t[:billed].positive? ? " (#{(v * 100.0 / t[:billed]).round}%)" : "" }
    rows = [
      [ "Billed", format_duration(t[:billed]), "Sum of billed time entries" ],
      [ "A · Item weights", format_duration(t[:items]) + pct.(t[:items]), "Each commit, PR, branch, deploy and review gets a time cost; commits scale with lines changed" ],
      [ "B · Activity sessions", format_duration(t[:sessions]) + pct.(t[:sessions]), "Events within #{est[:weights][:session_gap]} min are one session, plus #{est[:weights][:lead_in]} min lead-in" ],
      [ "C · Hackatime coded", format_duration(t[:coded]) + pct.(t[:coded]), "Editor and terminal heartbeats only" ]
    ]
    @document.table(rows, width: @document.bounds.width, column_widths: { 0 => 120, 1 => 90 }) do |tb|
      tb.cells.border_width = 0
      tb.cells.padding = [ 5, 6, 5, 0 ]
      tb.cells.size = 9
      tb.column(0).font_style = :bold
      tb.column(2).text_color = TEXT_SECONDARY
      tb.rows(0..-1).border_bottom_width = 0.5
      tb.rows(0..-1).border_bottom_color = BORDER_COLOR
    end
    @document.move_down 16
    day_rows = [ [ "Day", "Billed", "A · items", "B · sessions", "C · coded" ] ] +
      est[:days].map { |d| [ Date.parse(d[:date]).strftime("%a %b %-d"), *[ d[:billed], d[:items], d[:sessions], d[:coded] ].map { |v| v.positive? ? format_duration(v) : "—" } ] }
    @document.table(day_rows, width: @document.bounds.width, header: true) do |tb|
      tb.cells.border_width = 0
      tb.cells.padding = [ 3, 6, 3, 0 ]
      tb.cells.size = 8.5
      tb.row(0).font_style = :bold
      tb.row(0).text_color = TEXT_SECONDARY
      tb.row(0).border_bottom_width = 1
      tb.row(0).border_bottom_color = BORDER_COLOR
      tb.columns(1..4).align = :right
    end
  end

  def format_minutes(seconds)
    m = (seconds.to_i / 60.0).round
    m < 60 ? "#{m}m" : format("%dh %02dm", m / 60, m % 60)
  end

  def format_duration(seconds)
    seconds = seconds.to_i
    h, rem = seconds.divmod(3600)
    m = rem / 60
    h.positive? ? format("%d:%02d", h, m) : "0:#{format('%02d', m)}"
  end

  def format_currency(cents)
    return "$0.00" if cents.nil?

    "$#{format("%.2f", cents / 100.0)}"
  end

  def format_date(date)
    return "N/A" if date.nil?

    date.strftime("%b %d, %Y")
  end

  def invoice_number
    "#{@invoice.id.to_s(16).upcase.rjust(8, '0')}-#{@invoice.id.to_s.rjust(4, '0')}"
  end

  def sanitize_text(text)
    return nil if text.nil?

    text
      .gsub(/\x00/, "")
      .gsub(/[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]/, "")
      .strip
  end
end
