# frozen_string_literal: true

# An example of a custom chart. Any class that extends ChartBase can be called from inside
# html_report by its name in snake_case, so this one is invoked as `flow_metrics_summary`. See
# https://jirametrics.org/config/project/#custom-charts
#
# Summarizes the flow metrics per issue type, so a reader can see the shape of the period before
# scrolling into the charts themselves. These are operational measures taken from the system, not
# business outcomes, so read them as a description of how work moved rather than as a scorecard.
#
#   html_report do
#     flow_metrics_summary do
#       cycle_time_thresholds good: 10, warning: 20
#       throughput_thresholds good: 20, warning: 10
#     end
#   end

require 'jirametrics/chart_base'

class FlowMetricsSummary < ChartBase
  SECONDS_PER_DAY = 24 * 60 * 60
  DOT_COLORS = { 'good' => '#009E73', 'warning' => '#F0E442', 'bad' => '#D55E00' }.freeze

  def initialize block
    super()

    header_text 'Flow Metrics Summary'
    description_text <<~HTML
      <div class="p">
        Headline numbers for this period, split by issue type. Cycle time and flow efficiency are
        averaged across the items that completed inside the report's date range, so a type with
        only one or two completions will move around a lot between reports.
      </div>
      <style>
        .flow-metrics-summary table.standard { border-collapse: collapse; }
        .flow-metrics-summary th { text-align: left; padding: 8px 12px; border-bottom: 2px solid #ddd; }
        .flow-metrics-summary td { padding: 8px 12px; border-bottom: 1px solid #eee; }
        .flow-metrics-summary td:nth-child(n+2) { text-align: right; }
        .flow-metrics-summary .dot { display: inline-block; width: 12px; height: 12px; margin-left: 8px; }
        .flow-metrics-summary tr:hover td { background-color: #f5f5f5; }
      </style>
    HTML

    @thresholds = {}
    instance_eval(&block)
  end

  # Thresholds are opt in. Set none and the table reports numbers without grading them, which is
  # usually what you want until you have enough history to know what good looks like for this team.
  # For cycle time and WIP a lower number is better, so `good` is the smaller of the two.
  def cycle_time_thresholds good:, warning:
    @thresholds[:cycle_time] = { good: good, warning: warning, lower_is_better: true }
  end

  def wip_thresholds good:, warning:
    @thresholds[:wip] = { good: good, warning: warning, lower_is_better: true }
  end

  def throughput_thresholds good:, warning:
    @thresholds[:throughput] = { good: good, warning: warning, lower_is_better: false }
  end

  def flow_efficiency_thresholds good:, warning:
    @thresholds[:flow_efficiency] = { good: good, warning: warning, lower_is_better: false }
  end

  def run
    rows = [summarize('All', issues)]
    issues.filter_map(&:type).uniq.sort.each do |type|
      rows << summarize(type, issues.select { |issue| issue.type == type })
    end

    return render_no_data if rows.all? { |row| row[:throughput].zero? && row[:wip].zero? }

    html = render_top_text + seam_start + '<div class="flow-metrics-summary">'
    html += render_table(rows) + '</div>'
    html += '<div class="p"><strong>Flow Efficiency</strong> measures the ratio of active work time to total cycle time, expressed as a percentage. It indicates how much of the time an issue spends in the system is actually spent working on it versus waiting. A higher percentage means less waiting and more efficient flow. Flow efficiency is calculated as: <em>(active time / total cycle time) × 100</em>.</div>'
    html + seam_end
  end

  private

  def summarize type, issues_of_type
    completed = issues_of_type.select { |issue| completed_in_range?(issue) }
    {
      type: type,
      wip: issues_of_type.count { |issue| in_progress?(issue) },
      throughput: completed.size,
      cycle_time: average(completed.filter_map { |issue| cycle_time_in_days(issue) }),
      flow_efficiency: average(completed.filter_map { |issue| flow_efficiency_percent(issue) })
    }
  end

  # Deliberately the project's own cycletime configuration rather than a resolution date, so these
  # numbers agree with every other chart in the same report.
  def started_stopped issue
    cycletime_for_issue(issue).started_stopped_times(issue)
  end

  def completed_in_range? issue
    _started, stopped = started_stopped(issue)
    stopped && date_range.include?(stopped.to_date)
  end

  def in_progress? issue
    started, stopped = started_stopped(issue)
    started && stopped.nil?
  end

  def cycle_time_in_days issue
    started, stopped = started_stopped(issue)
    return nil unless started && stopped

    (stopped - started) / SECONDS_PER_DAY
  end

  def flow_efficiency_percent issue
    _started, stopped = started_stopped(issue)
    return nil unless stopped

    active, total = issue.flow_efficiency_numbers(end_time: stopped)
    return nil if total.zero?

    active / total * 100.0
  end

  def average values
    return nil if values.empty?

    values.sum / values.size.to_f
  end

  # Returns 'good', 'warning', 'bad', or nil when no threshold was configured for this metric.
  def rating key, value
    threshold = @thresholds[key]
    return nil if threshold.nil? || value.nil?

    good, warning = threshold.values_at(:good, :warning)
    if threshold[:lower_is_better]
      rate value, good: ->(v) { v <= good }, warning: ->(v) { v <= warning }
    else
      rate value, good: ->(v) { v >= good }, warning: ->(v) { v >= warning }
    end
  end

  def rate value, good:, warning:
    return 'good' if good.call(value)
    return 'warning' if warning.call(value)

    'bad'
  end

  def dot rating
    return '' if rating.nil?

    "<span class='dot' title='#{rating}' style=\"color: #{DOT_COLORS[rating]}\">&#9679;</span> "
  end

  def threshold_tooltip key
    threshold = @thresholds[key]
    return nil unless threshold
    
    good = threshold[:good]
    warning = threshold[:warning]
    lower_is_better = threshold[:lower_is_better]
    
    metric_name = key.to_s.gsub('_', ' ').capitalize
    unit = key == :flow_efficiency ? '%' : (key == :cycle_time ? ' days' : '')
    
    if lower_is_better
      "#{metric_name} Thresholds: ≤ #{good}#{unit} (good), ≤ #{warning}#{unit} (warning), > #{warning}#{unit} (needs improvement)"
    else
      "#{metric_name} Thresholds: ≥ #{good}#{unit} (good), ≥ #{warning}#{unit} (warning), < #{warning}#{unit} (needs improvement)"
    end
  end

  def render_table rows
    html = +"<table class='standard'>\n<thead><tr>"
    ['Issue type', 'WIP', 'Completed', 'Cycle time (days)', 'Flow efficiency'].each do |heading|
      html << "<th>#{heading}</th>"
    end
    html << "</tr></thead>\n<tbody>\n"
    rows.each { |row| html << render_row(row) }
    html << "</tbody>\n</table>\n"
  end

  def render_row row
    cycle_time_title = threshold_tooltip(:cycle_time)
    throughput_title = threshold_tooltip(:throughput)
    wip_title = threshold_tooltip(:wip)
    flow_efficiency_title = threshold_tooltip(:flow_efficiency)
    
    cells = [
      row[:type],
      "<span #{wip_title ? "title='#{wip_title}'" : ''}>#{row[:wip]}#{dot rating(:wip, row[:wip])}</span>",
      "<span #{throughput_title ? "title='#{throughput_title}'" : ''}>#{row[:throughput]}#{dot rating(:throughput, row[:throughput])}</span>",
      "<span #{cycle_time_title ? "title='#{cycle_time_title}'" : ''}>#{format_number row[:cycle_time]}#{dot rating(:cycle_time, row[:cycle_time])}</span>",
      "<span #{flow_efficiency_title ? "title='#{flow_efficiency_title}'" : ''}>#{format_number row[:flow_efficiency], suffix: '%'}#{dot rating(:flow_efficiency, row[:flow_efficiency])}</span>"
    ]
    "<tr>#{cells.map { |cell| "<td>#{cell}</td>" }.join}</tr>\n"
  end

  def format_number value, suffix: ''
    return '&mdash;' if value.nil?

    "#{value.round(1)}#{suffix}"
  end
end
