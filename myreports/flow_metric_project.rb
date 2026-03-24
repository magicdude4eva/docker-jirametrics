
class Exporter

  ### --------------------------------------------------------------------------------------------
  ### Project settings
  def flow_metric_project name:, file_prefix:, ignore_issues: nil, starting_status: nil, boards: {},
      default_board: nil, anonymize: false, settings: {}, status_category_mappings: {},
      rolling_date_count: 90, no_earlier_than: nil, ignore_types: %w[Sub-task Subtask Epic],
      show_experimental_charts: false, github_repos: nil
    exporter = self
    project name: name do
      puts name
      file_prefix file_prefix

      self.anonymize if anonymize
      self.settings.merge! stringify_keys(settings)

      boards.each_key do |board_id|
        block = boards[board_id]
        if block == :default
          block = lambda do |_|
            start_at first_time_in_status_category(:indeterminate)
            stop_at still_in_status_category(:done)
          end
        end
        board id: board_id do
          cycletime(&block)
        end
      end

      status_category_mappings.each do |status, category|
        status_category_mapping status: status, category: category
      end

      download do
        self.rolling_date_count(rolling_date_count) if rolling_date_count
        self.no_earlier_than(no_earlier_than) if no_earlier_than
        github_repo github_repos if github_repos
      end

      issues.reject! do |issue|
        ignore_types.include? issue.type
      end

      exporter.filter_issues issues, ignore_issues

      discard_changes_before status_becomes: (starting_status || :backlog) # rubocop:disable Style/RedundantParentheses

      file do
        file_suffix '.html'

        html_report do
          board_id default_board if default_board

          html "<H1>Flow metrics: #{name}</H1>", type: :header
          boards.each_key do |id|
            board = find_board id
            html "<div><a href='#{board.url}'>#{id} #{board.name}</a> (#{board.board_type})</div>",
                 type: :header
          end

          # Daily view
          daily_view

          # 1 Work in Progress
          daily_wip_by_age_chart
          daily_wip_by_blocked_stalled_chart
          daily_wip_by_parent_chart

          # 2 Throughput
          throughput_chart do
            description_text <<-HTML
              <div>
                <p>Throughput is the number of items completed in a period of time. We measure every Monday morning how many items have completed
                since the previous Monday morning.
                </p>
                Throughput data is very useful for#{' '} <a href="https://blog.mikebowler.ca/2024/06/02/probabilistic-forecasting/">probabilistic forecasting</a>,
                to determine when we'll be done. Try it now with the
                <a href="<%= throughput_forecaster_url %>" target="_blank" rel="noopener noreferrer">
                Focused Objective throughput forecaster,</a> to see how long it would take to complete all of the
                <%= @not_started_count %> items you currently have in your backlog.
              </div>
              <h2>Number of items completed, grouped by issue type</h2>
              <div class="p">
               We show throughput based on <b>work-item type</b>.
              </div>
            HTML
          end
          throughput_chart do
            header_text nil
            description_text <<-HTML
              <h2>Number of items completed, grouped by completion status and resolution</h2>
              <div class="p">
                We show throughput based on <b>completion status</b> and <b>resolution</b>.
              </div>
            HTML
            grouping_rules do |issue, rules|
              status, resolution = issue.status_resolution_at_done
              if resolution
                rules.label = "#{status.name}:#{resolution}"
              else
                rules.label = status.name
              end
            end
          end
		  

          # 3 Cycle Time
          cycletime_scatterplot do
            show_trend_lines
          end
          cycletime_histogram do
          end

          # 4 Work Item Age
          aging_work_in_progress_chart
          aging_work_bar_chart
          aging_work_table

          # Other charts
          cumulative_flow_diagram do
            column_rules do |column, rule|
              # Set colours
              rule.color = case column.name
                  when 'In Progress'
                    '#ffd058'
                  when 'Implementing'
                    '#dd6bac'
                  when 'Implemented'
                    '#ffabae'
                  when 'Merged'
                    '#aa5eaa'
                  when 'Verified'
                    '#a7d2fc'
                  when 'Done'
                    '#0291bb'
              end
            end
            arrival_rate_line_color   '#ff4c3a'
            departure_rate_line_color '#640574'
            triangle_color            '#ffff00'
          end

          flow_efficiency_scatterplot
          #sprint_burndown
		  
          expedited_chart
		  
		  # Pullrequest
### Jirametrics only supports Github, hence commented out for now
if false
          pull_request_cycle_time_histogram do
            cycletime_unit :hours
          end
          pull_request_cycle_time_scatterplot do
            cycletime_unit :hours
          end
end
### Jirametrics only supports Github, hence commented out for now
		  # Dependency chart
          dependency_chart
		  
        end
      end
    end
  end

  # Extracted as a separate method so it can be tested independently, without needing to invoke
  # the full standard_project DSL setup.
  def filter_issues issues, ignore_issues
    return unless ignore_issues

    issues.reject! do |issue|
      ignore_issues.is_a?(Proc) ? ignore_issues.call(issue) : ignore_issues.include?(issue.key)
    end
  end

  ### --------------------------------------------------------------------------------------------
  ### Eurofunk aggregated
  def flow_metric_aggregated_project name:, project_names:, settings: {}
    project name: name do
      puts name
      file_prefix name
      self.settings.merge! stringify_keys(settings)

      aggregate do
        project_names.each do |project_name|
          include_issues_from project_name
        end
      end

      file do
        file_suffix '.html'
        issues.reject! do |issue|
          %w[Sub-task Epic].include? issue.type
        end

        html_report do
          html '<h1>eOCS>COM Aggregated report</h1><ul>', type: :header
          board_lines = []
          included_projects.each do |project|
            project.all_boards.each_value do |board|
              board_lines << "<a href='#{project.get_file_prefix}.html'>#{board.name}</a> from project #{project.name}"
            end
          end
          board_lines.sort.each { |line| html "<li>#{line}</li>", type: :header }
          html '</ul>', type: :header

          cycletime_scatterplot do
            show_trend_lines
            # For an aggregated report we group by board rather than by type
            grouping_rules do |issue, rules|
              rules.label = issue.board.name
            end
          end
          # aging_work_in_progress_chart
          daily_wip_by_parent_chart do
            # When aggregating, the chart tends to need more vertical space
            canvas height: 400, width: 800
          end
          aging_work_table do
            # In an aggregated report, we likely only care about items that are old so exclude anything
            # under 21 days.
            age_cutoff 21
          end

          dependency_chart do
            header_text 'Dependencies across boards'
            description_text 'We are only showing dependencies across boards.'

            # By default, the issue doesn't show what board it's on and this is important for an
            # aggregated view
            chart = self
            issue_rules do |issue, rules|
              chart.default_issue_rules.call(issue, rules)
              rules.label = rules.label.split('<BR/>').insert(1, "Board: #{issue.board.name}").join('<BR/>')
            end

            link_rules do |link, rules|
              chart.default_link_rules.call(link, rules)

              # Because this is the aggregated view, let's hide any link that doesn't cross boards.
              rules.ignore if link.origin.board == link.other_issue.board
            end
          end
        end
      end
    end
  end

  
  
  
  
end
