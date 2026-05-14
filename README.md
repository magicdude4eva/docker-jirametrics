[paypal]: https://paypal.me/GerdNaschenweng

# 📊 Flow Metrics JiraMetrics

![GitHub stars](https://img.shields.io/github/stars/magicdude4eva/docker-jirametrics?style=social)
![Build](https://img.shields.io/badge/build-passing-brightgreen)
![GitHub forks](https://img.shields.io/github/forks/magicdude4eva/docker-jirametrics?style=social)
![GitHub issues](https://img.shields.io/github/issues/magicdude4eva/docker-jirametrics)
[![GitHub last commit](https://img.shields.io/github/last-commit/magicdude4eva/docker-jirametrics.svg)](https://github.com/magicdude4eva/docker-jirametrics/commits/master)
![License](https://img.shields.io/github/license/magicdude4eva/docker-jirametrics)

A Dockerized setup for [JiraMetrics](https://jirametrics.org/), automating the generation and serving of Jira flow metrics reports.

## Features
- **Automated reports**: Updates every 30 minutes via cron.
- **Self-contained**: HTML reports served via lightweight HTTP server.
- **Easy setup**: Uses Docker and `docker-compose`.

## Prerequisites
- Docker and Docker Compose installed.

## Usage
1. Clone this repository or download this repository
2. Download [Rancher Desktop](https://rancherdesktop.io/) or use WSL2 / Docker Engine etc
3. Adjust config in `./myreports` -> refer to [JiraMetrics](https://jirametrics.org/) for configuration:
   * Configure `jira.config` with your [Jira personal access token or API key](https://jirametrics.org/jira/)
   * Adjust the `config.rb` to your board / team needs
5. Run `docker-compose up --build`.
6. Access reports at [http://localhost:8000](http://localhost:8000).

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
- See [JiraMetrics Configuration Guide](https://jirametrics.org/configuration/) for details on how to configure `config.rb`.
- Place your `config.rb` in the `./myreports` directory.

## About JiraMetrics
This project uses [mikebowler/jirametrics](https://github.com/mikebowler/jirametrics), a tool for analyzing Jira workflows, cycle time, and throughput. See [jirametrics.org](https://jirametrics.org) for details.

### Feature: Dataquality report gives insight into the state of data
<img width="1886" height="528" alt="image" src="https://github.com/user-attachments/assets/83dd3461-4058-4bbe-9983-ee05fce29ad1" />

### Feature: WIP grouped by age / grouped by stalled
<img width="1883" height="669" alt="image" src="https://github.com/user-attachments/assets/5d18afe3-697a-479e-88e7-146f00c6a23f" />
<img width="1891" height="728" alt="image" src="https://github.com/user-attachments/assets/2af7ba45-73ae-4511-bb2a-ac3873c1c0a8" />

### Feature: Throughput chart by issue type and by completion status
<img width="1870" height="551" alt="image" src="https://github.com/user-attachments/assets/54eb07ac-a3a9-4ca9-8c1b-6ac180d35ca6" />
<img width="1881" height="553" alt="image" src="https://github.com/user-attachments/assets/dd47b5b8-1c90-4fdf-963c-da2219264e4d" />

### Feature: Cumulative Flow Diagram
<img width="1886" height="744" alt="image" src="https://github.com/user-attachments/assets/d2615b1b-a883-4ed5-be1d-a5362f0b976b" />

## 📄 License
This project is licensed under the [MIT License](LICENSE).

---

## ❤️ Contributing
PRs welcome! File issues or ideas via GitHub.

## Donations are always welcome

[paypal]: https://paypal.me/GerdNaschenweng

🍻 **Support my work**  
All my software is free and built in my personal time. If it helps you or your business, please consider a small donation via [PayPal][paypal] — it keeps the coffee ☕ and ideas flowing!

💸 **Crypto Donations**  
You can also send crypto to one of the addresses below:

```
(BTC)   bc1qdgdkk7l98pje8ny9u4xavsvrea8dw6yu8jpnyf
(ETH)   0x5986f713A538D6bCaC0865564dCD45E2600A3469  
(POL)   0x5986f713A538D6bCaC0865564dCD45E2600A3469
(CRO)   0xb83c3Fe378F5224fAdD7a0f8a7dD33a6C96C422C (Cronos or Crypto.com Paystring magicdude$paystring.crypto.com)
(BNB)   0x5986f713A538D6bCaC0865564dCD45E2600A3469
(LTC)   ltc1qexst2exxksfyg7erfzlfrm23twkjgf7e5fn64t
(DOGE)  DMQsxc9XGF6526drBJDZeX7AjFDJsEz4mN
(SOL)   t4bYQCUuoCUrp7kJ4Mz314npcTuKoUSXj28UgdMrfTb
```

🧾 **Recommended Platforms**  
- 👉 [Curve.com](https://www.curve.com/join#DWPXKG6E): Add your Crypto.com card to Apple Pay  
- 🔐 [Crypto.com](https://crypto.com/app/ref6ayzqvp): Stake and get your free Crypto Visa card  
- 📈 [Binance](https://accounts.binance.com/register?ref=13896895): Trade altcoins easily



