# Use the official CRuby image as base
FROM ruby:3.2

# Install dependencies
RUN apt-get update && \
    apt-get install -y \
    graphviz \
    cron \
    python3 \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Install jirametrics (with optional pre-release)
ARG INSTALL_PRE=false
RUN if [ "$INSTALL_PRE" = "true" ]; then \
        gem install jirametrics --pre; \
    else \
        gem install jirametrics; \
    fi

# Create entrypoint.sh on the fly
RUN { \
    echo '#!/bin/bash'; \
    echo 'set -e'; \
    echo ''; \
    echo 'echo "[INFO] Starting Flow Metrics JiraMetrics container..."'; \
    echo ''; \
    echo 'if [ "$INSTALL_PRE" != "true" ]; then'; \
    echo '  echo "[INFO] Checking for updates..."'; \
    echo '  GITHUB_API_URL="https://api.github.com/repos/mikebowler/jirametrics/releases/latest"'; \
    echo '  CURRENT_VERSION_FILE="/config/current_version.txt"'; \
    echo '  GEM_NAME="jirametrics"'; \
    echo ''; \
    echo '  # Create current_version.txt if it does not exist'; \
    echo '  if [ ! -f "$CURRENT_VERSION_FILE" ]; then'; \
    echo '    echo "0.0.0" > "$CURRENT_VERSION_FILE"'; \
    echo '  fi'; \
    echo ''; \
    echo '  # Fetch the latest version from GitHub'; \
    echo '  LATEST_VERSION=$(curl -s "$GITHUB_API_URL" | jq -r ".tag_name" | sed "s/^v//")'; \
    echo '  CURRENT_VERSION=$(cat "$CURRENT_VERSION_FILE")'; \
    echo ''; \
    echo '  # Compare versions'; \
    echo '  if [ "$LATEST_VERSION" != "$CURRENT_VERSION" ]; then'; \
    echo '    echo "[INFO] A new version of $GEM_NAME is available: v$LATEST_VERSION"'; \
    echo '    echo "[INFO] Updating..."'; \
    echo '    if gem install $GEM_NAME; then'; \
    echo '      echo "$LATEST_VERSION" > "$CURRENT_VERSION_FILE"'; \
    echo '      echo "[INFO] Update successful."'; \
    echo '    else'; \
    echo '      echo "[ERROR] Update failed." >&2'; \
    echo '      exit 1'; \
    echo '    fi'; \
    echo '  else'; \
    echo '    echo "[INFO] $GEM_NAME is up to date: v$CURRENT_VERSION"'; \
    echo '  fi'; \
    echo 'else'; \
    echo '  echo "[INFO] Pre-release mode enabled. Skipping update check."'; \
    echo 'fi'; \
    echo ''; \
    echo 'echo "[INFO] Starting cron..."'; \
    echo '# Write the cron file with the expanded CRON_SCHEDULE'; \
    echo 'echo "SHELL=/bin/bash" > /etc/cron.d/jirametrics-cron'; \
    echo 'echo "${CRON_SCHEDULE:-*/30 * * * *} root cd /config && jirametrics go >> /var/log/cron.log 2>&1" >> /etc/cron.d/jirametrics-cron'; \
    echo 'echo "" >> /etc/cron.d/jirametrics-cron'; \
    echo 'chmod 0644 /etc/cron.d/jirametrics-cron'; \
    echo 'crontab /etc/cron.d/jirametrics-cron'; \
    echo 'cron && tail -f /var/log/cron.log &'; \
    echo ''; \
    echo 'echo "[INFO] Checking if initial reports need to be generated..."'; \
    echo '[ -z "$(ls -A /config/target 2>/dev/null)" ] && echo "[INFO] /config/target is empty. Running jirametrics go for the first time..." && jirametrics go'; \
    echo ''; \
    echo 'echo "[INFO] Starting HTTP server on port 8000..."'; \
    echo 'cd /config/target && python3 -m http.server 8000'; \
    } > /entrypoint.sh && \
    chmod +x /entrypoint.sh

# Create config and target directories
RUN mkdir -p /config/target
VOLUME /config

# Expose HTTP port
EXPOSE 8000

# Entrypoint
ENTRYPOINT ["/entrypoint.sh"]
