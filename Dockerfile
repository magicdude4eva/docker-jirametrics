FROM ruby:3.2-slim

ARG INSTALL_PRE=false
ARG SUPERCRONIC_VERSION=v0.2.43

ENV APP_DIR=/app \
    CONFIG_DIR=/config \
    PORT=8000 \
    CRON_SCHEDULE="*/30 * * * *" \
    INSTALL_PRE=${INSTALL_PRE}

WORKDIR ${APP_DIR}

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    graphviz \
    jq \
    python3 \
    tini \
    util-linux \
    && rm -rf /var/lib/apt/lists/*

RUN if [ "$INSTALL_PRE" = "true" ]; then \
      gem install --no-document jirametrics --pre; \
    else \
      gem install --no-document jirametrics; \
    fi

RUN arch="$(dpkg --print-architecture)" && \
    case "$arch" in \
      amd64) sc_arch="amd64" ;; \
      arm64) sc_arch="arm64" ;; \
      armhf) sc_arch="arm" ;; \
      *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
    esac && \
    curl -fsSLo /usr/local/bin/supercronic \
      "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-${sc_arch}" && \
    chmod +x /usr/local/bin/supercronic

RUN mkdir -p /config/target /app

RUN cat > /usr/local/bin/entrypoint.sh <<'EOF'
#!/bin/sh
set -eu

echo "[INFO] Starting container..."
echo "[INFO] CRON_SCHEDULE=${CRON_SCHEDULE:-*/30 * * * *}"
echo "[INFO] INSTALL_PRE=${INSTALL_PRE:-false}"

mkdir -p /config /config/target /app

maybe_upgrade_jirametrics() {
  if [ "${INSTALL_PRE:-false}" = "true" ]; then
    echo "[INFO] INSTALL_PRE=true, skipping stable-release upgrade check."
    return 0
  fi

  echo "[INFO] Checking for jirametrics updates..."

  GITHUB_API_URL="https://api.github.com/repos/mikebowler/jirametrics/releases/latest"
  CURRENT_VERSION_FILE="/config/current_version.txt"
  GEM_NAME="jirametrics"

  if [ ! -f "$CURRENT_VERSION_FILE" ]; then
    installed_version="$(gem list "^${GEM_NAME}$" --no-versions >/dev/null 2>&1 && gem list "^${GEM_NAME}$" | awk 'NR==1 {gsub(/[()]/, "", $2); print $2}' || true)"
    if [ -n "${installed_version:-}" ]; then
      echo "$installed_version" > "$CURRENT_VERSION_FILE"
    else
      echo "0.0.0" > "$CURRENT_VERSION_FILE"
    fi
  fi

  CURRENT_VERSION="$(cat "$CURRENT_VERSION_FILE" 2>/dev/null || echo 0.0.0)"
  LATEST_VERSION="$(curl -fsSL "$GITHUB_API_URL" | jq -r '.tag_name' | sed 's/^v//' || true)"

  if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" = "null" ]; then
    echo "[WARN] Could not determine latest version from GitHub. Skipping upgrade check."
    return 0
  fi

  if [ "$LATEST_VERSION" != "$CURRENT_VERSION" ]; then
    echo "[INFO] New version available: v$LATEST_VERSION (current marker: v$CURRENT_VERSION)"
    echo "[INFO] Updating $GEM_NAME..."

    if gem install --no-document "$GEM_NAME"; then
      echo "$LATEST_VERSION" > "$CURRENT_VERSION_FILE"
      echo "[INFO] Update successful. Stored marker version: v$LATEST_VERSION"
    else
      echo "[ERROR] Update failed."
      return 1
    fi
  else
    echo "[INFO] $GEM_NAME is up to date: v$CURRENT_VERSION"
  fi
}

run_initial_generation() {
  if [ -z "$(ls -A /config/target 2>/dev/null || true)" ]; then
    echo "[INFO] /config/target is empty. Running initial generation..."
    (
      cd /config
      flock -n /tmp/jirametrics.lock jirametrics go
    ) || echo "[WARN] Initial generation failed."
  fi
}

write_crontab() {
  cat > /app/crontab <<CRON
${CRON_SCHEDULE:-*/30 * * * *} cd /config && flock -n /tmp/jirametrics.lock jirametrics go
CRON

  echo "[INFO] Effective crontab:"
  cat /app/crontab
}

shutdown() {
  echo "[INFO] Caught termination signal, shutting down..."
  kill -TERM "${SUPERCRONIC_PID:-}" "${HTTP_PID:-}" 2>/dev/null || true
  wait "${SUPERCRONIC_PID:-}" "${HTTP_PID:-}" 2>/dev/null || true
  exit 0
}

trap shutdown INT TERM

maybe_upgrade_jirametrics || true
run_initial_generation
write_crontab

/usr/local/bin/supercronic /app/crontab &
SUPERCRONIC_PID=$!

cd /config/target
python3 -m http.server "${PORT:-8000}" --bind 0.0.0.0 &
HTTP_PID=$!

wait "$SUPERCRONIC_PID" "$HTTP_PID"
exit $?
EOF

RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh && chmod +x /usr/local/bin/entrypoint.sh

VOLUME ["/config"]
EXPOSE 8000

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
