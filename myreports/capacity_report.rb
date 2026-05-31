# capacity_report.rb
# Capacity breakdown from jirametrics downloaded issues.
# Reads team config directly from config.rb — no duplication needed.
#
# Usage: ruby capacity_report.rb [path/to/config.rb]
#
# Analyzes worklog data from Jira (via jirametrics.org JSON exports) to show:
#   - Ignored maintenance issues with monthly breakdown
#   - Sub-task parent distribution (sorted: Feature first, then others)
#   - Monthly trend with focus mix and delta to previous month
#   - Capacity split by bucket (Feature/Bug/Other)
#   - Breakdown by issue type and worklog author
#   - Top representative issues per bucket
#   - Cross-team summary and pattern analysis

require 'json'
require 'date'

CONFIG_FILE = ARGV[0] || 'config.rb'
TARGET      = File.dirname(CONFIG_FILE) + '/target'
TOP_ISSUES  = 5
TOP_PERSONS = 10

CAPACITY_BUCKET = {
  'Feature'      => :feature,
  'Story'        => :feature,
  'Sub-Task'     => :inherit,
  'Bug'          => :bug,
  'Defect'       => :bug,
  'Task'         => :other,
  'Blocker'      => :other,
  'Epic'         => :other,
  'Program Epic' => :other,
}.freeze

BUCKET_LABEL = { feature: 'Feature work', bug: 'Bug / Defect', other: 'Other / Overhead' }.freeze
BUCKET_ORDER = %i[feature bug other].freeze

# ANSI colours — green/red/yellow blocks for focus bar
COL_FEATURE = "\e[32m"   # green
COL_BUG     = "\e[31m"   # red
COL_OTHER   = "\e[33m"   # yellow
COL_BLUE    = "\e[34m"   # blue
COL_RESET   = "\e[0m"

# Coloured symbols used throughout the report
SYM_WARN = "#{COL_OTHER}\u26a0#{COL_RESET}"    # ⚠ yellow
SYM_OK   = "#{COL_FEATURE}\u2713#{COL_RESET}"  # ✓ green
SYM_INFO = "#{COL_BLUE}\u2691#{COL_RESET}"     # ⚑ blue

# ── Parse config.rb ───────────────────────────────────────────────────────

def parse_config(path)
  abort "ERROR: config file not found: #{File.expand_path(path)}" unless File.exist?(path)
  source = File.read(path, encoding: 'utf-8')
  teams  = []

  blocks = source.scan(
    /^\s*flow_metric_project\s+name:.*?(?=^\s*flow_metric(?:_aggregated)?_project\s+name:|\z)/m
  ).reject { |b| b.strip.start_with?('flow_metric_aggregated_project') }

  blocks.each do |block|
    name        = block[/name:\s*['"](.+?)['"]/, 1]
    file_prefix = block[/file_prefix:\s*['"](.+?)['"]/, 1]
    no_earlier  = block[/no_earlier_than:\s*['"](\d{4}-\d{2}-\d{2})['"]/, 1]
    next unless name && file_prefix

    ignore_issues = []
    if (m = block[/ignore_issues:\s*\[(.+?)\]/m, 1])
      ignore_issues = m.scan(/['"]([A-Z]+-\d+)['"]/).flatten.reject { |k| k =~ /XXXX/i }
    end

    parent_fields = []
    if (m = block[/customfield_parent_links:\s*\[(.+?)\]/m, 1])
      parent_fields = m.scan(/['"](\w+)['"]/).flatten
    end

    teams << {
      name:            name,
      file_prefix:     file_prefix,
      no_earlier_than: no_earlier ? Date.parse(no_earlier) : nil,
      ignore_issues:   ignore_issues,
      parent_fields:   parent_fields
    }
  end

  abort "ERROR: No flow_metric_project entries found in #{path}" if teams.empty?
  teams
end

# ── Sprint string parser (Greenhopper legacy format) ─────────────────────

def parse_sprint_string(str)
  return nil unless str.is_a?(String) && str.include?('[')
  inner = str[/\[(.+)\]/m, 1]
  return nil unless inner
  result = {}
  %w[name state id].each do |key|
    result[key] = $1.strip if inner.match(/\b#{key}=([^,\]]+)/)
  end
  %w[startDate endDate].each do |key|
    if inner.match(/\b#{key}=(\d{4}-\d{2}-\d{2}[^,\]]*)/)
      val = $1.strip
      result[key] = Date.parse(val) rescue nil unless val == '<null>'
    end
  end
  result
end

def extract_sprint(fields)
  raw = fields['customfield_10004']
  return nil unless raw
  entries = raw.is_a?(Array) ? raw : [raw]
  entries.map { |s| parse_sprint_string(s) }.compact.last
end

# ── Helpers ───────────────────────────────────────────────────────────────

def fmt_pct(n)   = "#{n.round(1)}%".rjust(7)
def fmt_hours(s) = "#{(s / 3600.0).round(1)}h".rjust(8)

def fmt_focus_pcts(f, b, o)
  "F#{f.round.to_s.rjust(3)}% B#{b.round.to_s.rjust(3)}% O#{o.round.to_s.rjust(3)}%"
end

def load_issue(path)
  JSON.parse(File.read(path, encoding: 'utf-8'))
rescue JSON::ParserError, Encoding::UndefinedConversionError
  nil
end

def resolve_bucket(issue_type, parent_type)
  b = CAPACITY_BUCKET[issue_type] || :other
  b == :inherit ? (CAPACITY_BUCKET[parent_type] || :other) : b
end

# OLS slope in percentage-points per month over a series of values.
# Returns nil when fewer than 2 data points are available.
def linear_slope(values)
  n = values.size
  return nil if n < 2
  x_mean = (n - 1) / 2.0
  y_mean = values.sum.to_f / n
  num = values.each_with_index.sum { |y, i| (i - x_mean) * (y - y_mean) }
  den = values.each_with_index.sum { |_, i| (i - x_mean)**2 }
  den.zero? ? 0.0 : num / den
end

# ±1% deadband so minor month-to-month noise isn't called a trend.
def trend_arrow(slope, threshold: 1.0)
  return '→' if slope.nil? || slope.abs < threshold
  slope > 0 ? '↗' : '↘'
end

# Coloured delta: green = good direction, red = bad direction, plain = stable.
# good_up: true for Feature (rising is good), false for Bug/Other (rising is bad).
def fmt_delta(slope, good_up: true)
  arrow = trend_arrow(slope)
  color = if arrow == '→'
    ''
  elsif (arrow == '↗') == good_up
    COL_FEATURE  # green
  else
    COL_BUG      # red
  end
  "#{color}#{arrow}#{format('%+.1f', slope)}%#{COL_RESET unless color.empty?}"
end

# Returns [seconds_after_cutoff, oldest_entry_date, paginated?,
#          per_author_seconds { author_name => seconds }]
# Hours are attributed to WORKLOG AUTHOR (not issue assignee) for accuracy.
def worklog_seconds_from(fields, cutoff)
  wl_data      = fields['worklog'] || {}
  entries      = wl_data['worklogs'] || []
  paginated    = wl_data['total'].to_i > entries.size
  newest       = entries.map { |e| Date.parse(e['started']) rescue nil }.compact.max
  total_secs   = 0
  by_author    = Hash.new(0)
  by_month     = Hash.new(0)

  entries.each do |e|
    started = Date.parse(e['started']) rescue nil
    next unless started && (cutoff.nil? || started >= cutoff)
    secs   = e['timeSpentSeconds'].to_i
    author = e.dig('author', 'displayName') || 'Unassigned'
    total_secs        += secs
    by_author[author] += secs
    by_month[started.strftime('%Y-%m')] += secs
  end

  [total_secs, newest, paginated, by_author, by_month]
end

# ── Main ──────────────────────────────────────────────────────────────────

teams = parse_config(CONFIG_FILE)

puts "=== Capacity Report — #{Time.now.strftime('%Y-%m-%d %H:%M')} ==="
puts "    Config   : #{File.expand_path(CONFIG_FILE)}"
puts "    Scanning : #{File.expand_path(TARGET)}"
puts "    Teams    : #{teams.map { |t| t[:name] }.join(', ')}"
puts "    Note     : Hours attributed to worklog author. Representative issues show the top contributor by hours logged."
puts

abort "ERROR: '#{TARGET}' directory not found." unless Dir.exist?(TARGET)

all_teams_summary = []

teams.each do |team|
  prefix        = team[:file_prefix]
  name          = team[:name]
  cutoff        = team[:no_earlier_than]
  ignoring      = team[:ignore_issues]
  parent_fields = team[:parent_fields]

  issues_dir = "#{TARGET}/#{prefix}_issues"
  unless Dir.exist?(issues_dir)
    puts "[SKIP] #{name} — #{issues_dir}/ not found\n\n"
    next
  end

  json_files = Dir["#{issues_dir}/*.json"]
  if json_files.empty?
    puts "[SKIP] #{name} — no JSON files in #{issues_dir}/\n\n"
    next
  end

  # ── Load all issues once ──────────────────────────────────────────────
  all_issues = {}
  json_files.each do |path|
    raw = load_issue(path)
    next unless raw
    k = raw['key']
    next unless k
    all_issues[k] = raw
  end

  key_to_issue = all_issues.transform_values do |raw|
    {
      type:    raw.dig('fields', 'issuetype', 'name'),
      summary: (raw.dig('fields', 'summary') || '').strip
    }
  end

  # ── Analyse ──────────────────────────────────────────────────────────
  by_type   = Hash.new { |h, k| h[k] = { count: 0, seconds: 0 } }  # key: [issue_type, bucket]
  by_bucket = BUCKET_ORDER.each_with_object({}) { |b, h| h[b] = { count: 0, seconds: 0 } }

  # BY PERSON keyed by worklog AUTHOR
  by_person = Hash.new do |h, k|
    h[k] = { seconds: 0,
              by_bucket: BUCKET_ORDER.each_with_object({}) { |b, h2| h2[b] = 0 } }
  end

  subtask_parents         = Hash.new(0)
  bucket_issues           = BUCKET_ORDER.each_with_object({}) { |b, h| h[b] = [] }
  monthly                 = Hash.new { |h, k| h[k] = BUCKET_ORDER.each_with_object({}) { |b, h2| h2[b] = 0 } }
  ignored_count           = 0
  ignored_direct_seconds  = 0
  ignored_subtasks        = 0
  ignored_subtask_seconds = 0
  ignored_parent_summary  = Hash.new { |h, k| h[k] = { subtasks: 0, seconds: 0, direct_seconds: 0, by_month: {} } }
  pagination_ok           = 0
  pagination_warn         = 0
  pagination_unknown      = 0

  all_issues.each_value do |issue|
    fields     = issue['fields']
    next if fields.nil?

    issue_key  = issue['key']
    issue_type = fields.dig('issuetype', 'name') || 'Unknown'
    summary    = (fields['summary'] || '').strip

    # ── Resolve parent ────────────────────────────────────────────────
    parent_key  = fields.dig('parent', 'key')
    parent_type = fields.dig('parent', 'fields', 'issuetype', 'name')

    if parent_key.nil? || parent_type.nil?
      parent_fields.each do |cf|
        cf_val = fields[cf]
        if cf_val.is_a?(String) && !cf_val.empty?
          parent_key  ||= cf_val
          parent_type ||= key_to_issue.dig(cf_val, :type)
          break
        end
      end
    end

    # ── Skip directly ignored issues ─────────────────────────────────
    if ignoring.include?(issue_key)
      spent, _, _, _, by_month = worklog_seconds_from(fields, cutoff)
      ignored_count          += 1
      ignored_direct_seconds += spent
      rec = ignored_parent_summary[issue_key]
      rec[:direct_seconds]   += spent
      rec[:summary]         ||= (fields['summary'] || '').strip
      rec[:type]            ||= fields.dig('issuetype', 'name') || ''
      # Merge monthly breakdown
      by_month.each { |month, secs| rec[:by_month][month] = rec[:by_month].fetch(month, 0) + secs }
      next
    end

    # ── Skip Sub-Tasks whose parent is ignored ────────────────────────
    if issue_type == 'Sub-Task' && parent_key && ignoring.include?(parent_key)
      spent, _, _, _, by_month = worklog_seconds_from(fields, cutoff)
      ignored_subtasks        += 1
      ignored_subtask_seconds += spent
      rec = ignored_parent_summary[parent_key]
      rec[:subtasks] += 1
      rec[:seconds]  += spent
      rec[:summary]  ||= key_to_issue.dig(parent_key, :summary) || ''
      rec[:type]     ||= key_to_issue.dig(parent_key, :type) || ''
      # Merge monthly breakdown
      by_month.each { |month, secs| rec[:by_month][month] = rec[:by_month].fetch(month, 0) + secs }
      next
    end

    bucket = resolve_bucket(issue_type, parent_type)
    subtask_parents[parent_type || 'Unknown'] += 1 if issue_type == 'Sub-Task'

    # ── Worklogs ──────────────────────────────────────────────────────
    spent, newest, paginated, by_author, by_month = worklog_seconds_from(fields, cutoff)

    if paginated
      if newest.nil?
        pagination_unknown += 1
      elsif cutoff.nil? || newest >= cutoff
        pagination_ok += 1
      else
        pagination_warn += 1
      end
    end

    # ── Accumulate by type / bucket ───────────────────────────────────
    by_type[[issue_type, bucket]][:count]   += 1
    by_type[[issue_type, bucket]][:seconds] += spent

    by_bucket[bucket][:count]   += 1
    by_bucket[bucket][:seconds] += spent

    # ── Accumulate by WORKLOG AUTHOR ──────────────────────────────────
    by_author.each do |author, secs|
      by_person[author][:seconds]             += secs
      by_person[author][:by_bucket][bucket]   += secs
    end

    # ── Accumulate by month ─────────────────────────────────────────────────
    by_month.each { |month, secs| monthly[month][bucket] += secs }

    bucket_issues[bucket] << {
      key: issue_key, summary: summary, type: issue_type,
      hours: spent / 3600.0,
      top_author: by_author.max_by { |_, secs| secs }&.first || '—'
    }
  end

  total_count   = by_bucket.values.sum { |v| v[:count] }
  total_seconds = by_bucket.values.sum { |v| v[:seconds] }

  top_contributor = by_person.max_by { |_, v| v[:seconds] }
  top_contributor_data = if top_contributor && total_seconds > 0
    { name: top_contributor[0], pct: top_contributor[1][:seconds].to_f / total_seconds * 100 }
  end

  # ── Trend: OLS slope per bucket across monthly series ─────────────────
  trend_data = nil
  trend_months = monthly.keys.sort
  if trend_months.size >= 2
    series = trend_months.map do |m|
      data   = monthly[m]
      m_secs = data.values.sum.to_f
      next { f: 0.0, b: 0.0, o: 0.0 } if m_secs.zero?
      { f: data[:feature] / m_secs * 100,
        b: data[:bug]     / m_secs * 100,
        o: data[:other]   / m_secs * 100 }
    end
    trend_data = {
      feature: linear_slope(series.map { |s| s[:f] }),
      bug:     linear_slope(series.map { |s| s[:b] }),
      other:   linear_slope(series.map { |s| s[:o] }),
      months:  trend_months.size
    }
  end

  # Latest month's per-bucket percentages — used for accurate breach projection
  latest_pcts = nil
  if (last_month = trend_months.last)
    data   = monthly[last_month]
    m_secs = data.values.sum.to_f
    unless m_secs.zero?
      latest_pcts = {
        feature: data[:feature] / m_secs * 100,
        bug:     data[:bug]     / m_secs * 100,
        other:   data[:other]   / m_secs * 100
      }
    end
  end

  all_teams_summary << {
    name: name, total_count: total_count,
    total_seconds: total_seconds, by_bucket: by_bucket,
    task_subtask_count: subtask_parents['Task'] || 0,
    top_contributor: top_contributor_data,
    trend: trend_data,
    latest_pcts: latest_pcts
  }

  # ════════════════════════════════════════════════════════════════════
  # Output
  # ════════════════════════════════════════════════════════════════════
  cutoff_label  = cutoff ? cutoff.to_s : 'all time'
  total_ignored = ignored_count + ignored_subtasks
  ignored_label = total_ignored > 0 ? ", #{total_ignored} ignored" : ''
  puts "┌─ #{COL_BLUE}#{name}#{COL_RESET} ─ #{json_files.size} issues#{ignored_label} ─ worklogs from #{cutoff_label}"

  # ── Ignored summary ───────────────────────────────────────────────
  if total_ignored > 0
    puts "│"
    # Get last two months for header
    all_months = ignoring.map { |key| ignored_parent_summary[key][:by_month].keys }.flatten.uniq.sort
    last_two_months = all_months.last(2)

    # Build header based on available months
    month_headers = last_two_months
    header_suffix = month_headers.empty? ? '' : '  ' + month_headers.map { |m| m.rjust(8) }.join('  ')
    separator_suffix = month_headers.empty? ? '' : '  ' + month_headers.map { |_| '-' * 8 }.join('  ')

    puts "│  #{COL_OTHER}IGNORED (team-specific issues + their sub-tasks)#{COL_RESET}"
    puts "│  #{'Parent Key'.ljust(14)} #{'Type'.ljust(12)} #{'Sub-Tasks'.rjust(9)}  #{'Hours*'.rjust(8)}#{header_suffix}  Summary"
    puts "│  #{'-' * 14} #{'-' * 12} #{'-' * 9}  #{'-' * 8}#{separator_suffix}  #{'-' * 36}"
    ignoring.each do |key|
      meta = key_to_issue[key]
      next unless meta
      rec        = ignored_parent_summary[key]
      subtasks   = rec[:subtasks] > 0 ? rec[:subtasks].to_s : '—'
      total_secs = rec[:seconds] + rec[:direct_seconds]
      hours      = total_secs > 0 ? "%.1fh" % (total_secs / 3600.0) : '—'
      # Format last two months
      month_values = last_two_months.map do |m|
        secs = rec[:by_month][m] || 0
        month_hours = secs > 0 ? "%.1fh" % (secs / 3600.0) : '—'
        month_hours.rjust(8)
      end
      month_str = month_values.empty? ? '' : '  ' + month_values.join('  ')
      puts "│  #{key.ljust(14)} #{meta[:type].to_s.ljust(12)} #{subtasks.rjust(9)}  #{hours.rjust(8)}#{month_str}  #{meta[:summary][0..35]}"
    end
    puts "│  → #{ignored_count} parent issue(s) excluded (#{('%.1fh' % (ignored_direct_seconds/3600.0))} on parent after #{cutoff})"
    puts "│  → #{ignored_subtasks} sub-task(s) excluded (#{('%.1fh' % (ignored_subtask_seconds/3600.0))} logged after #{cutoff})"
    puts "│  * Hours include worklogs on parent + sub-tasks after #{cutoff}."
  end

  # ── Pagination ────────────────────────────────────────────────────
  total_paginated = pagination_ok + pagination_warn + pagination_unknown
  if total_paginated > 0
    puts "│"
    puts "│  #{SYM_OK}  PAGINATION: #{pagination_ok} issue(s) paginated; fetched page straddles #{cutoff} — in-window entries captured." if pagination_ok > 0
    puts "│  #{SYM_WARN}  PAGINATION: #{pagination_warn} issue(s) fetched page entirely pre-#{cutoff}; in-window worklogs may be on unfetched pages." if pagination_warn > 0
    puts "│     #{pagination_unknown} paginated with no entries to verify." if pagination_unknown > 0
  end

  # ── Sub-Task parent breakdown ──────────────────────────────────────
  total_subtasks = subtask_parents.values.sum
  if total_subtasks > 0
    non_feature = subtask_parents.reject { |pt, _| %w[Story Feature].include?(pt) }
    if non_feature.any?
      puts "│"
      puts "│  #{SYM_INFO}  SUB-TASK PARENTS (#{total_subtasks} remaining after ignored exclusions)"
      subtask_parents.sort_by { |_, v| -v }.each do |pt, count|
        b    = resolve_bucket('Sub-Task', pt == 'Unknown' ? nil : pt)
        flag = b == :feature ? "#{SYM_OK} feature" : "→ #{BUCKET_LABEL[b]}"
        note = pt == 'Unknown' ? ' (parent not in download — check board filter)' : ''
        puts "│     #{count.to_s.rjust(4)}  parent: #{pt.to_s.ljust(18)} #{flag}#{note}"
      end
    end
  end

  puts "│"

  # ── Capacity split ─────────────────────────────────────────────────
  # Grand total includes ignored issues so percentages reflect true capacity
  grand_count   = total_count   + ignored_count + ignored_subtasks
  grand_seconds = total_seconds + ignored_subtask_seconds + ignored_direct_seconds

  puts "│  #{COL_OTHER}CAPACITY SPLIT#{COL_RESET}"
  puts "│  #{'Bucket'.ljust(18)} #{'Items'.rjust(6)}  #{'Items%'.rjust(7)}  #{'Hours'.rjust(8)}  #{'Hours%'.rjust(7)}"
  puts "│  #{'-' * 18} #{'-' * 6}  #{'-' * 7}  #{'-' * 8}  #{'-' * 7}"
  BUCKET_ORDER.each do |b|
    d = by_bucket[b]
    next if d[:count] == 0
    item_pct = grand_count   > 0 ? d[:count].to_f   / grand_count   * 100 : 0
    hour_pct = grand_seconds > 0 ? d[:seconds].to_f / grand_seconds * 100 : 0
    puts "│  #{BUCKET_LABEL[b].ljust(18)} #{d[:count].to_s.rjust(6)}  #{fmt_pct(item_pct)}  #{fmt_hours(d[:seconds])}  #{fmt_pct(hour_pct)}"
  end
  if total_ignored > 0
    ign_items         = ignored_count + ignored_subtasks
    ign_total_seconds = ignored_direct_seconds + ignored_subtask_seconds
    item_pct  = grand_count   > 0 ? ign_items.to_f         / grand_count   * 100 : 0
    hour_pct  = grand_seconds > 0 ? ign_total_seconds.to_f / grand_seconds * 100 : 0
    puts "│  #{'Ignored issues'.ljust(18)} #{ign_items.to_s.rjust(6)}  #{fmt_pct(item_pct)}  #{fmt_hours(ign_total_seconds)}  #{fmt_pct(hour_pct)}"
  end
  puts "│  #{'-' * 18} #{'-' * 6}  #{'-' * 7}  #{'-' * 8}  #{'-' * 7}"
  puts "│  #{'GRAND TOTAL'.ljust(18)} #{grand_count.to_s.rjust(6)}  #{'100%'.rjust(7)}  #{fmt_hours(grand_seconds)}  #{'100%'.rjust(7)}"

  # ── Monthly trend ────────────────────────────────────────────────────────
  unless monthly.empty?
    current_month = Date.today.strftime('%Y-%m')
    sorted_months = monthly.keys.sort
    puts "│"
    puts "│  #{COL_OTHER}MONTHLY TREND#{COL_RESET}"
    puts "│  #{'Month'.ljust(9)} #{'Hours'.rjust(8)}  #{'Feat%'.rjust(7)}  #{'Bug%'.rjust(7)}  #{'Other%'.rjust(7)}  Mix                   Δ prev"
    puts "│  #{'-' * 9} #{'-' * 8}  #{'-' * 7}  #{'-' * 7}  #{'-' * 7}  #{'-' * 20}  #{'-' * 26}"
    prev_pcts = nil
    sorted_months.each do |month|
      data   = monthly[month]
      m_secs = data.values.sum
      next if m_secs == 0
      f_pct = data[:feature].to_f / m_secs * 100
      b_pct = data[:bug].to_f     / m_secs * 100
      o_pct = data[:other].to_f   / m_secs * 100
      bw    = 20
      fw    = (f_pct / 100.0 * bw).round
      bw2   = (b_pct / 100.0 * bw).round
      ow    = [bw - fw - bw2, 0].max
      bar   = "#{COL_FEATURE}#{'█' * fw}#{COL_BUG}#{'█' * bw2}#{COL_OTHER}#{'█' * ow}#{COL_RESET}"
      label = month == current_month ? "#{month} *" : month
      delta_str = if prev_pcts
        df  = f_pct - prev_pcts[:f]
        db  = b_pct - prev_pcts[:b]
        do_ = o_pct - prev_pcts[:o]
        "F#{fmt_delta(df, good_up: true)} B#{fmt_delta(db, good_up: false)} O#{fmt_delta(do_, good_up: false)}"
      else
        '—'
      end
      puts "│  #{label.ljust(9)} #{fmt_hours(m_secs)}  #{fmt_pct(f_pct)}  #{fmt_pct(b_pct)}  #{fmt_pct(o_pct)}  #{bar}  #{delta_str}"
      prev_pcts = { f: f_pct, b: b_pct, o: o_pct }
    end
    puts "│  (* current month — partial)" if monthly.key?(current_month)
  end

  # ── By issue type ──────────────────────────────────────────────────
  puts "│"
  puts "│  #{COL_OTHER}BY ISSUE TYPE (Sub-Tasks inherit parent bucket)#{COL_RESET}"
  puts "│  #{'Type'.ljust(14)} #{'Bucket'.ljust(16)} #{'Items'.rjust(6)}  #{'Hours'.rjust(8)}  #{'Hours%'.rjust(7)}"
  puts "│  #{'-' * 14} #{'-' * 16} #{'-' * 6}  #{'-' * 8}  #{'-' * 7}"
  by_type.sort_by { |(type, bucket), d| [BUCKET_ORDER.index(bucket) || 99, -d[:seconds]] }.each do |(type, bucket), data|
    next if data[:count] == 0
    hour_pct = total_seconds > 0 ? data[:seconds].to_f / total_seconds * 100 : 0
    puts "│  #{type.ljust(14)} #{BUCKET_LABEL[bucket].ljust(16)} #{data[:count].to_s.rjust(6)}  #{fmt_hours(data[:seconds])}  #{fmt_pct(hour_pct)}"
  end

  # ── By person (worklog author) ─────────────────────────────────────
  puts "│"
  puts "│  #{COL_OTHER}BY PERSON — hours by worklog author, focus spread (F=Feature B=Bug O=Other)#{COL_RESET}"
  puts "│  #{'Author'.ljust(28)} #{'Hours'.rjust(8)}  #{'H%'.rjust(6)}  Focus"
  puts "│  #{'-' * 28} #{'-' * 8}  #{'-' * 6}  #{'-' * 42}"
  by_person.sort_by { |_, v| -v[:seconds] }.first(TOP_PERSONS).each do |author, data|
    next if data[:seconds] == 0
    hour_pct = total_seconds > 0 ? data[:seconds].to_f / total_seconds * 100 : 0
    ps = data[:seconds].to_f
    f_pct = data[:by_bucket][:feature] / ps * 100
    b_pct = data[:by_bucket][:bug]     / ps * 100
    o_pct = data[:by_bucket][:other]   / ps * 100
    bw    = 20
    fw    = (f_pct / 100 * bw).round
    bw2   = (b_pct / 100 * bw).round
    ow    = [bw - fw - bw2, 0].max
    bar    = "#{COL_FEATURE}#{'█' * fw}#{COL_BUG}#{'█' * bw2}#{COL_OTHER}#{'█' * ow}#{COL_RESET}"
    spread = "#{bar} #{fmt_focus_pcts(f_pct, b_pct, o_pct)}"
    puts "│  #{author.ljust(28)} #{fmt_hours(data[:seconds])}  #{fmt_pct(hour_pct)}  #{spread}"
  end

  # ── Representative issues ──────────────────────────────────────────
  puts "│"
  puts "│  #{COL_OTHER}REPRESENTATIVE ISSUES — top #{TOP_ISSUES} by hours per bucket#{COL_RESET}"
  BUCKET_ORDER.each do |b|
    top = bucket_issues[b].sort_by { |i| -i[:hours] }.reject { |i| i[:hours] == 0 }.first(TOP_ISSUES)
    next if top.empty?
    puts "│"
    puts "│  ▸ #{BUCKET_LABEL[b].upcase}"
    puts "│    #{'Hours'.rjust(7)}  #{'Top contributor'.ljust(24)} Key + Summary"
    puts "│    #{'-' * 7}  #{'-' * 24} #{'-' * 40}"
    top.each do |i|
      puts "│    #{('%.1fh' % i[:hours]).rjust(7)}  #{i[:top_author].ljust(24)} #{i[:key]}  #{i[:summary][0..49]}"
    end
  end

  puts "└#{'─' * 105}\n\n"
end

# ── Cross-cutting patterns ───────────────────────────────────────────────────────────
puts
puts "╔══ #{COL_BLUE}CROSS-CUTTING PATTERNS#{COL_RESET} #{'═' * 79}"
puts "║"
puts "\u2551  #{'Team'.ljust(22)} #{'Total h'.rjust(8)} #{'Feat%'.rjust(7)}  #{'Bug%'.rjust(7)}  #{'Other%'.rjust(7)}  #{'Trend'.ljust(9)}  Signals"
puts "\u2551  #{'-' * 22} #{'-' * 8} #{'-' * 7}  #{'-' * 7}  #{'-' * 7}  #{'-' * 9}  #{'-' * 30}"

all_teams_summary.each do |t|
  ts = t[:total_seconds].to_f
  if ts == 0
    puts "║  #{t[:name].ljust(22)}   — (no logged hours)"
    next
  end
  f_pct = t[:by_bucket][:feature][:seconds] / ts * 100
  b_pct = t[:by_bucket][:bug][:seconds]     / ts * 100
  o_pct = t[:by_bucket][:other][:seconds]   / ts * 100
  signals = []
  signals << "Bug #{b_pct.round}%"      if b_pct > 20
  signals << "Other #{o_pct.round}%"    if o_pct > 25
  signals << "Feature #{f_pct.round}%" if f_pct < 50
  tc = t[:top_contributor]
  signals << "SPOF #{tc[:name].split.first} #{tc[:pct].round}%" if tc && tc[:pct] > 30
  td = t[:trend]
  if td
    f_proj = f_pct + 2 * td[:feature].to_f
    b_proj = b_pct + 2 * td[:bug].to_f
    o_proj = o_pct + 2 * td[:other].to_f
    signals << "Feat\u2198#{format('%.1f', td[:feature].abs)}%" if f_pct >= 50 && f_proj < 50
    signals << "Bug\u2197#{format('%.1f', td[:bug].abs)}%"      if b_pct <= 20 && b_proj > 20
    signals << "Other\u2197#{format('%.1f', td[:other].abs)}%"  if o_pct <= 25 && o_proj > 25
  end
  trend_col = if td
    fa = trend_arrow(td[:feature]); fc = fa == '→' ? '' : fa == '↗' ? COL_FEATURE : COL_BUG
    ba = trend_arrow(td[:bug]);     bc = ba == '→' ? '' : ba == '↗' ? COL_BUG     : COL_FEATURE
    oa = trend_arrow(td[:other]);   oc = oa == '→' ? '' : oa == '↗' ? COL_BUG     : COL_FEATURE
    "#{fc}F#{fa}#{COL_RESET unless fc.empty?} " \
    "#{bc}B#{ba}#{COL_RESET unless bc.empty?} " \
    "#{oc}O#{oa}#{COL_RESET unless oc.empty?} "
  else
    '—'.ljust(9)
  end
  flag = signals.empty? ? "#{SYM_OK} all clear" : "#{SYM_WARN}  #{signals.join(' · ')}"
  puts "║  #{t[:name].ljust(22)} #{fmt_hours(ts)} #{fmt_pct(f_pct)}  #{fmt_pct(b_pct)}  #{fmt_pct(o_pct)}  #{trend_col}  #{flag}"
end

# ── Textual analysis ───────────────────────────────────────────────────────────
active = all_teams_summary.select { |t| t[:total_seconds] > 0 }
if active.size >= 2
  in_breach = active.select { |t|
    ts = t[:total_seconds].to_f
    tc = t[:top_contributor]
    t[:by_bucket][:bug][:seconds]     / ts * 100 > 20 ||
    t[:by_bucket][:other][:seconds]   / ts * 100 > 25 ||
    t[:by_bucket][:feature][:seconds] / ts * 100 < 50 ||
    (tc && tc[:pct] > 30)
  }

  with_trend = active.select { |t| t[:trend] }

  approaching = (active - in_breach).select { |t|
    td = t[:trend]; next false unless td
    ts = t[:total_seconds].to_f
    f  = t[:by_bucket][:feature][:seconds] / ts * 100
    b  = t[:by_bucket][:bug][:seconds]     / ts * 100
    o  = t[:by_bucket][:other][:seconds]   / ts * 100
    (f >= 50 && f + 2 * td[:feature].to_f < 50) ||
    (b <= 20 && b + 2 * td[:bug].to_f     > 20) ||
    (o <= 25 && o + 2 * td[:other].to_f   > 25)
  }

  healthy = active - in_breach - approaching

  most_urgent = in_breach.max_by { |t|
    t[:by_bucket][:bug][:seconds].to_f / t[:total_seconds]
  }

  fastest_decline = with_trend.min_by { |t| t[:trend][:feature].to_f }
  fastest_decline = nil if fastest_decline.nil? || fastest_decline[:trend][:feature].to_f >= -1.0

  best_recovery = with_trend.max_by { |t| t[:trend][:feature].to_f }
  best_recovery = nil if best_recovery.nil? || best_recovery[:trend][:feature].to_f <= 1.0

  bug_rising = with_trend.count { |t| t[:trend][:bug].to_f > 1.0 }

  puts "║"
  puts "║  Analysis:"
  [
    ['In breach  ', in_breach],
    ['Approaching', approaching],
    ['Healthy    ', healthy],
  ].each do |label, group|
    names = group.empty? ? '—' : group.map { |t| t[:name] }.join(' · ')
    puts "║    #{label} : #{names}"
  end
  puts "║"

  if in_breach.empty? && approaching.empty?
    puts "║  #{SYM_OK}  All teams are within thresholds with no breaches approaching."
  else
    if most_urgent
      ts    = most_urgent[:total_seconds].to_f
      b_pct = most_urgent[:by_bucket][:bug][:seconds] / ts * 100
      td    = most_urgent[:trend]
      slope = td && td[:bug].to_f > 1.0 ? ", rising #{format('%.1f', td[:bug])}%/mo" : ''
      puts "║  #{SYM_WARN}  Most urgent: #{most_urgent[:name]} Bug at #{b_pct.round(1)}%#{slope}."
    end

    if fastest_decline
      slope   = fastest_decline[:trend][:feature].to_f
      f_now   = fastest_decline[:latest_pcts]&.dig(:feature) ||
                fastest_decline[:by_bucket][:feature][:seconds].to_f / fastest_decline[:total_seconds] * 100
      timing  = f_now >= 50 ? " — breach in ~#{((f_now - 50.0) / slope.abs).ceil}mo" : ''
      puts "║  #{SYM_WARN}  Fastest decline: #{fastest_decline[:name]} Feature " \
           "falling #{format('%.1f', slope.abs)}%/mo#{timing}."
    end

    if best_recovery
      slope = best_recovery[:trend][:feature].to_f
      note  = in_breach.include?(best_recovery) ? ' (still in breach)' : ''
      puts "║  #{SYM_OK}  Strongest recovery: #{best_recovery[:name]} Feature rising " \
           "#{format('%.1f', slope)}%/mo#{note} — best momentum this period."
    end

    if bug_rising >= 3 && with_trend.size >= 3
      puts "║  ~  Portfolio: Bug rising in #{bug_rising} of #{with_trend.size} teams " \
           "— systemic signal worth raising at programme level."
    end
  end
end

distorted = all_teams_summary.select { |t| t[:task_subtask_count] >= 10 }.sort_by { |t| -t[:task_subtask_count] }
if distorted.any?
  puts "║"
  puts "║  Sub-task/Task bucketing distortion (→ Other% may be overstated):"
  distorted.each do |t|
    puts "║    #{t[:name].ljust(22)} : #{t[:task_subtask_count].to_s.rjust(3)} sub-tasks under Task parents"
  end
end
puts "║"
puts "║  Signal thresholds:"
[
  ['muda',  'Bug%',        '>',  '20%',  'quality debt & interrupt load consuming capacity'],
  ['mura',  'Other%',      '>',  '25%',  'overhead crowding out value delivery'],
  ['',      'Feat%',       '<',  '50%',  'less than half of effort on value-adding work'],
  ['muri',  'SPOF',        '>',  '30%',  'one person carrying a disproportionate team load'],
  ['trend', 'X↘/↗N%',   nil,  nil,    'metric rate/mo trending toward threshold (early warning)'],
].each do |label, metric, op, val, description|
  condition = op ? "#{metric.rjust(6)} #{op} #{val}" : metric
  puts "║    #{label.ljust(5)} #{condition.ljust(13)}— #{description}"
end
puts "╚#{'═' * 105}"
