# Flow Metrics JiraMetrics

A Dockerized setup for [JiraMetrics](https://jirametrics.org/), automating the generation and serving of Jira flow metrics reports.

## Features
- **Automated reports**: Updates every 30 minutes via cron.
- **Self-contained**: HTML reports served via lightweight HTTP server.
- **Easy setup**: Uses Docker and `docker-compose`.

## Prerequisites
- Docker and Docker Compose installed.

## Usage
1. Clone this repository.
2. Run `docker-compose up --build`.
3. Access reports at [http://localhost:8000](http://localhost:8000).

## Configuration
- Set `INSTALL_PRE=true` in `docker-compose.yml` for pre-release builds.
- Adjust `CRON_SCHEDULE` to change update frequency.

## About JiraMetrics
This project uses [mikebowler/jirametrics](https://github.com/mikebowler/jirametrics), a tool for analyzing Jira workflows, cycle time, and throughput. See [jirametrics.org](https://jirametrics.org) for details.
