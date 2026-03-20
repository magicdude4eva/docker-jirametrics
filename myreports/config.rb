# =============================================================================
# Jirametrics Configuration for Flow Metric Projects
# =============================================================================
#
# SUMMARY
# -------
# Jirametrics is a tool for extracting and visualizing metrics from Jira.
# It helps teams track progress, identify bottlenecks, and improve workflows.
# For more information, visit: https://jirametrics.org/
#
# Look at commits -> https://github.com/mikebowler/jirametrics/commits/main/
#
# Configure `config.rb`:
#    Customize this file to define your projects, boards, and metrics.
#    For more details, see: https://jirametrics.org/config/
#
# =============================================================================
require_relative 'flow_metric_project'

Exporter.configure do

	# Output directory for generated reports
	target_path 'target/'
	
	 # Jira configuration file
	jira_config 'jira.config'

	# Timezone offset for date/time calculations
	timezone_offset '+01:00'
	
	#List of holiday dates for velocity calculations (Austrian holidays)
	holiday_dates '2025-11-01', '2025-12-08', '2025-12-24', '2025-12-25', '2025-12-26', '2025-12-31',
                  '2026-01-01', '2026-01-06', '2026-04-06', '2026-05-01', '2026-05-14', '2026-05-25',
                  '2026-06-04', '2026-08-15', '2026-10-26', '2026-11-01', '2026-12-08', '2026-12-24',
                  '2026-12-25', '2026-12-26', '2026-12-31', '2027-01-01', '2027-01-06'

	# Project Configuration
	# ------------------------------	
	# 1) Team A
	flow_metric_project name: 'Team A',
		file_prefix: 'team-a',
		rolling_date_count: 90,
		no_earlier_than: '2026-01-01',
		#starting_status: 'In Progress',
		boards: {
			0000 => lambda do |_|
						start_at first_time_in_status('In Progress','Developing')
						stop_at still_in_status_category('Done')
					end
		},
		ignore_issues: ['ABC'],
		settings: {
			date_annotations: [
				{ date: "2026-01-12T11:00:00", label: "Some annotation" },
				{ date: "2026-02-13T09:00:00", label: "Another annotation" }
			],
			#blocked_statuses: ['Blocked'],
			# The number of days of inactivity (no comments, movement of a a subtask, status changes or updates of any kind)
			# before an item becomes considered stalled.
			stalled_threshold_days: 5,
			# A list of statuses that should be considered stalled, same as blocked above.
			# This is useful if you have queues in your workflow where the work is just sitting and waiting for someone to free up.
			stalled_statuses: ['Ready for Review','Ready for Verification','Ready for Acceptance'],
			expedited_priority_names: ['Highest','Critical']
		}
		#ignore_types: ['Sub-task']

	# 2) Team B
	flow_metric_project name: 'Team B',
		file_prefix: 'team-b',
		rolling_date_count: 90,
		no_earlier_than: '2026-01-01',
		#starting_status: 'In Progress',
		boards: {
			1252 => lambda do |_|
						start_at first_time_in_status('In Progress','Developing')
						stop_at still_in_status_category('Done')
					end
		},
		ignore_issues: ['ABC'],
		settings: {
			date_annotations: [
				{ date: "2026-01-12T11:00:00", label: "Some annotation" },
				{ date: "2026-02-13T09:00:00", label: "Another annotation" }
			],
			#blocked_statuses: ['Blocked'],
			# The number of days of inactivity (no comments, status changes or updates of any kind) before an item becomes considered stalled.
			stalled_threshold_days: 5,
			# A list of statuses that should be considered stalled, same as blocked above.
			# This is useful if you have queues in your workflow where the work is just sitting and waiting for someone to free up.
			stalled_statuses: ['Ready for Review','Ready for Verification','Ready for Acceptance'],
			expedited_priority_names: ['Highest','Critical']
		}
		#ignore_types: ['Sub-task']

	# 3) Aggregation across two teams
	flow_metric_aggregated_project name: 'Team Aggregated', project_names: ['Team A', 'Team B']

end
