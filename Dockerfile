#
# Flow Metrics JiraMetrics Container
#
# This image runs JiraMetrics in a self-contained container and serves the
# generated HTML reports over a lightweight Python HTTP server.
#
# Runtime behavior:
# - JiraMetrics configuration and generated files live under /config
# - JiraMetrics writes raw artifacts and reports into /config/target
# - Only generated *.html files are published to /config/www
# - The HTTP server serves /config/www on PORT
# - INDEX_FILE can be used to publish one selected report as /index.html
# - If INDEX_FILE is not set or not found, the first available HTML file is
#   copied to /config/www/index.html
# - Supercronic runs `jirametrics go` on the configured CRON_SCHEDULE
# - On container startup, JiraMetrics is installed or upgraded to either the
#   stable or pre-release version, depending on INSTALL_PRE
#
# Environment variables:
#   APP_DIR             Application working directory (default: /app)
#   CONFIG_DIR          Persistent JiraMetrics config/report directory (default: /config)
#   PORT                Port used by the Python HTTP server (default: 8000)
#   CRON_SCHEDULE       Schedule for periodic JiraMetrics runs
#                       (default: "*/30 * * * *")
#   INSTALL_PRE         If "true", installs the JiraMetrics pre-release gem;
#                       otherwise installs the stable gem (default: false)
#   INDEX_FILE          Optional report file to expose as /index.html
#                       Example: "/Team Alpha.html"
#
# Build arguments:
#   INSTALL_PRE         Default value propagated into the runtime environment
#   SUPERCRONIC_VERSION Version of Supercronic to install (default: v0.2.44)
#
# Exposed volume:
#   /config             Persistent storage for JiraMetrics config and outputs
#
# Exposed port:
#   8000                Default HTTP port inside the container
#
# Notes:
# - This image intentionally serves only curated HTML output from /config/www
#   instead of exposing the full /config/target directory listing
# - Because JiraMetrics is installed at startup, container start time depends
#   on gem installation and network availability
#
FROM ruby:3.3-slim

# ---- Build args ----
ARG INSTALL_PRE=false
ARG SUPERCRONIC_VERSION=v0.2.44

ENV APP_DIR=/app \
    CONFIG_DIR=/config \
    PORT=8000 \
    CRON_SCHEDULE="*/30 * * * *" \
    INSTALL_PRE=${INSTALL_PRE} \
    INDEX_FILE=""

WORKDIR ${APP_DIR}

# ---- System deps ----
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    graphviz \
    jq \
    python3 \
    tini \
    util-linux \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

# ---- Install Supercronic ----
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

RUN mkdir -p /config/target /config/www /app

# ---- Single source of truth for publishing HTML files ----
RUN cat > /usr/local/bin/refresh-public.sh <<'EOF'
#!/bin/sh
set -eu

echo "[INFO] Refreshing /config/www from /config/target ..."
mkdir -p /config/www

# Remove previously published HTML files
find /config/www -mindepth 1 -maxdepth 1 -type f -name '*.html' -delete

# Copy current HTML reports
find /config/target -maxdepth 1 -type f -name '*.html' -exec cp -f {} /config/www/ \;

# Create default index.html
if [ -n "${INDEX_FILE:-}" ]; then
  index_name="$(basename "${INDEX_FILE}")"
  if [ -f "/config/www/${index_name}" ]; then
    cp -f "/config/www/${index_name}" /config/www/index.html
    echo "[INFO] Using configured index file: ${index_name}"
    exit 0
  else
    echo "[WARN] INDEX_FILE '${INDEX_FILE}' not found in /config/target"
  fi
fi

first_html="$(find /config/www -maxdepth 1 -type f -name '*.html' ! -name 'index.html' | sort | head -n 1 || true)"
if [ -n "${first_html}" ]; then
  cp -f "${first_html}" /config/www/index.html
  echo "[INFO] Using fallback index file: $(basename "${first_html}")"
else
  echo "[WARN] No HTML files available for index.html"
fi
EOF

RUN cat > /usr/local/bin/entrypoint.sh <<'EOF'
#!/bin/sh
set -eu

echo "[INFO] Starting container..."
echo "[INFO] CRON_SCHEDULE=${CRON_SCHEDULE:-*/30 * * * *}"
echo "[INFO] INSTALL_PRE=${INSTALL_PRE:-false}"
echo "[INFO] INDEX_FILE=${INDEX_FILE:-}"
echo "[INFO] PORT=${PORT:-8000}"

mkdir -p /config /config/target /config/www /app

upgrade_jirametrics() {
  if [ "${INSTALL_PRE:-false}" = "true" ]; then
    echo "[INFO] Upgrading Jirametrics pre-release version..."
    gem install --no-document jirametrics --pre
  else
    echo "[INFO] Upgrading Jirametrics stable version..."
    gem install --no-document jirametrics
  fi
}

run_generation() {
  echo "[INFO] Running jirametrics go ..."
  (
    cd /config
    flock -n /tmp/jirametrics.lock sh -c 'jirametrics go && /usr/local/bin/refresh-public.sh'
  ) || echo "[WARN] jirametrics run skipped or failed."
}

run_initial_generation() {
  if [ -z "$(find /config/target -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1 || true)" ]; then
    echo "[INFO] /config/target is empty. Running initial generation..."
    run_generation
  else
    echo "[INFO] /config/target already contains files. Refreshing public directory..."
    /usr/local/bin/refresh-public.sh
  fi
}

write_crontab() {
  cat > /app/crontab <<CRON
${CRON_SCHEDULE:-*/30 * * * *} cd /config && flock -n /tmp/jirametrics.lock sh -c 'jirametrics go && /usr/local/bin/refresh-public.sh'
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

upgrade_jirametrics
write_crontab
run_initial_generation

/usr/local/bin/supercronic -passthrough-logs /app/crontab &
SUPERCRONIC_PID=$!

cd /config/www
python3 -m http.server "${PORT:-8000}" --bind 0.0.0.0 &
HTTP_PID=$!

wait "$SUPERCRONIC_PID" "$HTTP_PID"
exit $?
EOF


RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh /usr/local/bin/refresh-public.sh && \
    chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/refresh-public.sh

VOLUME ["/config"]
EXPOSE 8000

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
