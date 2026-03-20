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
2. Adjust config in `./myreports` -> refer to [JiraMetrics](https://jirametrics.org/) for configuration.
3. Run `docker-compose up --build`.
4. Access reports at [http://localhost:8000](http://localhost:8000).

## Environment Variables
| Variable          | Default Value       | Description                                      |
|-------------------|---------------------|--------------------------------------------------|
| `INSTALL_PRE`     | `false`             | Install pre-release version of JiraMetrics.      |
| `CRON_SCHEDULE`   | `*/30 * * * *`      | Cron schedule for report updates (e.g., every 30 min). |

## Data Persistence
- Reports and configuration files are stored in the `./myreports` directory on your host machine.
- This directory is mounted to `/config` inside the container.

## First Run
- On first run, if the `./myreports/target` directory is empty, the container will automatically generate initial reports.

## Upgrades
- The container checks for updates on startup (unless `INSTALL_PRE=true`).
- Updates are applied automatically if a new version is available.

## Configuration
- Set `INSTALL_PRE=true` in `docker-compose.yml` for pre-release builds.
- Adjust `CRON_SCHEDULE` to change update frequency.

## Example Configuration
- See [JiraMetrics Configuration Guide](https://jirametrics.org/configuration/) for details on how to configure `config.yml`.
- Place your `config.yml` in the `./myreports` directory.

## About JiraMetrics
This project uses [mikebowler/jirametrics](https://github.com/mikebowler/jirametrics), a tool for analyzing Jira workflows, cycle time, and throughput. See [jirametrics.org](https://jirametrics.org) for details.
