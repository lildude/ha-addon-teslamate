#!/usr/bin/env bash
# setup-ha.sh - Idempotent Home Assistant setup for addon development
#
# This script:
# 1. Completes HA onboarding (creates admin user)
# 2. Adds the alexbelgium addon repository (for PostgreSQL)
# 3. Installs and starts PostgreSQL 17
# 4. Installs, configures, and starts the local addon
#
# Usage: bash .devcontainer/setup-ha.sh
#        DEBUG=1 bash .devcontainer/setup-ha.sh   # verbose output + error details
#
# Safe to run multiple times (idempotent).

set -euo pipefail

# --- Addon-specific configuration ---
ADDON_NAME="$(jq -r '.name' config.json)"
ADDON_SLUG="local_$(jq -r '.slug' config.json)"
ADDON_PORT="$(jq -r '.ports | keys[0] | split("/") | .[0]' config.json)"
ADDON_READY_LOG="TeslaMateWeb.Endpoint"
TIMEZONE="Europe/London"

# --- Home Assistant configuration ---
HA_HOST="localhost"
# Core binds port 80 under the Supervisor from 2026.8 onwards, and 8123 before
# that, so wait_for_ha resolves the port at runtime rather than assuming one.
HA_PORTS=(80 8123)
HA_URL=""
CLIENT_ID=""
ALEXBELGIUM_REPO="https://github.com/alexbelgium/hassio-addons"
ADMIN_USER="admin"
ADMIN_PASS="pass"

# --- PostgreSQL configuration ---
POSTGRES_PASSWORD="homeassistant"
POSTGRES_USER="postgres"
POSTGRES_DB="${ADDON_NAME,,}"
POSTGRES_PORT=5432
# Addon slug = repo_hash + "_" + addon_slug_from_config
# Repo hash: first 8 chars of sha1("https://github.com/alexbelgium/hassio-addons")
POSTGRES_SLUG="db21ed7f_postgres_latest"

# --- Helpers ---
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log()  { echo -e "${CYAN}==>${NC} ${BOLD}$*${NC}"; }
warn() { echo -e "${YELLOW}WARNING:${NC} $*" >&2; }
err()  { echo -e "${RED}ERROR:${NC} $*" >&2; exit 1; }
ok()   { echo -e "${CYAN}==>${NC} ${GREEN}$*${NC}"; }

# Parse JSON, aborting with the offending body instead of a bare jq parse error
jq_or_die() {
  local json="$1" filter="$2" context="$3"
  if [ -z "$json" ] || ! jq empty <<< "$json" 2>/dev/null; then
    err "${context}: expected JSON, got: ${json}"
  fi
  jq -r "$filter" <<< "$json"
}

# Run Supervisor API call via hassio_cli container
# IMPORTANT: Use single quotes for outer sh -c argument so $SUPERVISOR_TOKEN
# is expanded by the inner shell (where the env var exists), not the outer bash.
supervisor_api() {
  local method="$1" endpoint="$2"
  docker exec hassio_cli sh -c \
    'curl -s -X '"${method}"' -H "Authorization: Bearer $SUPERVISOR_TOKEN" -H "Content-Type: application/json" http://supervisor'"${endpoint}"
}

supervisor_api_with_body() {
  local method="$1" endpoint="$2" body="$3"
  docker exec -e "BODY=${body}" hassio_cli sh -c \
    'curl -s -X '"${method}"' -H "Authorization: Bearer $SUPERVISOR_TOKEN" -H "Content-Type: application/json" -d "$BODY" http://supervisor'"${endpoint}"
}

# Query a specific jq field from a Supervisor API response.
# Supervisor reports HTTP errors as plain text (e.g. "404: Not Found"), which is
# not JSON, so surface those and return nothing to let callers keep polling.
supervisor_api_jq() {
  local endpoint="$1" jq_filter="$2"
  local response
  response=$(supervisor_api GET "${endpoint}")
  if [ -z "$response" ] || ! jq empty <<< "$response" 2>/dev/null; then
    warn "Supervisor API ${endpoint} returned non-JSON: ${response}"
    return 0
  fi
  jq -r "$jq_filter" <<< "$response"
}

# Check if a jq expression matches (returns 0 if match found, 1 otherwise)
supervisor_api_jq_test() {
  local endpoint="$1" jq_filter="$2"
  docker exec -e "JQ_FILTER=${jq_filter}" hassio_cli sh -c \
    'curl -s -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor'"${endpoint}"' | jq -e "$JQ_FILTER" > /dev/null 2>&1'
}

# --- Step 0: Wait for HA to be ready ---

# Print an addon's log to help diagnose a failure
dump_addon_logs() {
  local slug="$1"
  echo "::group::${slug} logs"
  supervisor_api GET "/addons/${slug}/logs" || true
  echo "::endgroup::"
}

# Best-effort Home Assistant Core state from the Supervisor, for diagnostics
ha_core_state() {
  local info
  info=$(supervisor_api GET "/core/info" 2>/dev/null) || true
  if [ -n "$info" ] && jq empty <<< "$info" 2>/dev/null; then
    jq -r '.data.state // "unknown"' <<< "$info"
  else
    echo "unavailable"
  fi
}

# HA answers on its HTTP port long before the API is usable, and from 2026.8 the
# port itself moved from 8123 to 80 under the Supervisor. Older releases still use
# 8123, and during onboarding new releases answer on both - but 8123 only serves a
# redirect that Core tears down once onboarding completes. So port 80 is tried
# first, redirects are deliberately not followed, and a port only counts as ready
# when it serves the onboarding payload itself rather than merely valid JSON.
HA_PROBE=""

ha_probe() {
  local port="$1" raw status body
  raw=$(curl -s --max-time 5 -w $'\n%{http_code}' "http://${HA_HOST}:${port}/api/onboarding" 2>/dev/null || true)
  status=${raw##*$'\n'}
  body=${raw%$'\n'*}
  HA_PROBE="${HA_PROBE:+${HA_PROBE} }port=${port} http=${status:-none} body=${body:0:80}"
  jq -e 'type == "array" and (.[0] | has("step"))' <<< "$body" > /dev/null 2>&1
}

# Sets HA_URL and CLIENT_ID on success. Must not run in a subshell.
ha_resolve_url() {
  local port
  HA_PROBE=""
  for port in "${HA_PORTS[@]}"; do
    if ha_probe "$port"; then
      HA_URL="http://${HA_HOST}:${port}"
      CLIENT_ID="${HA_URL}/"
      return 0
    fi
  done
  return 1
}

wait_for_ha() {
  log "Waiting for Home Assistant to be ready..."
  local max_attempts=120
  local attempt=0
  while [ "$attempt" -lt "$max_attempts" ]; do
    if ha_resolve_url; then
      ok "Home Assistant is ready at ${HA_URL}"
      return 0
    fi
    if [ $((attempt % 6)) -eq 0 ]; then
      log "  attempt ${attempt}/${max_attempts}: core=$(ha_core_state) ${HA_PROBE}"
    fi
    sleep 5
    attempt=$((attempt + 1))
  done
  err "Home Assistant did not become ready in time (core=$(ha_core_state) ${HA_PROBE})"
}

# --- Step 1: Complete onboarding ---

complete_onboarding() {
  log "Checking onboarding status..."
  local onboarding
  onboarding=$(curl -sfL "${HA_URL}/api/onboarding")

  local user_done
  user_done=$(jq_or_die "$onboarding" '.[] | select(.step == "user") | .done' "Onboarding status")

  if [ "$user_done" = "true" ]; then
    ok "Onboarding already completed"
    return 0
  fi

  log "Creating admin user '${ADMIN_USER}'..."
  local auth_response
  auth_response=$(curl -sfL -X POST "${HA_URL}/api/onboarding/users" \
    -H "Content-Type: application/json" \
    -d "{\"client_id\":\"${CLIENT_ID}\",\"name\":\"Admin\",\"username\":\"${ADMIN_USER}\",\"password\":\"${ADMIN_PASS}\",\"language\":\"en\"}")

  local auth_code
  auth_code=$(jq_or_die "$auth_response" '.auth_code' "Create admin user")

  if [ -z "$auth_code" ] || [ "$auth_code" = "null" ]; then
    err "Failed to create user: ${auth_response}"
  fi

  # Exchange auth code for access token
  local token_response
  token_response=$(curl -sfL -X POST "${HA_URL}/auth/token" \
    --data-urlencode "grant_type=authorization_code" \
    --data-urlencode "code=${auth_code}" \
    --data-urlencode "client_id=${CLIENT_ID}")

  local access_token
  access_token=$(jq_or_die "$token_response" '.access_token' "Token exchange")

  if [ -z "$access_token" ] || [ "$access_token" = "null" ]; then
    err "Failed to get access token: ${token_response}"
  fi

  # Complete remaining onboarding steps
  log "Completing onboarding steps..."
  curl -sfL -X POST "${HA_URL}/api/onboarding/core_config" \
    -H "Authorization: Bearer ${access_token}" \
    -H "Content-Type: application/json" \
    -d "{}" > /dev/null 2>&1 || true

  curl -sfL -X POST "${HA_URL}/api/onboarding/analytics" \
    -H "Authorization: Bearer ${access_token}" \
    -H "Content-Type: application/json" \
    -d "{}" > /dev/null 2>&1 || true

  curl -sfL -X POST "${HA_URL}/api/onboarding/integration" \
    -H "Authorization: Bearer ${access_token}" \
    -H "Content-Type: application/json" \
    -d "{\"client_id\":\"${CLIENT_ID}\",\"redirect_uri\":\"${HA_URL}/\"}" > /dev/null 2>&1 || true

  ok "Onboarding complete"
}

# --- Step 2: Add alexbelgium addon repository ---

add_addon_repo() {
  log "Checking addon repositories..."

  if supervisor_api_jq_test "/store/repositories" ".data[] | select(.source == \"${ALEXBELGIUM_REPO}\")"; then
    ok "Repository already added: ${ALEXBELGIUM_REPO}"
    return 0
  fi

  log "Adding addon repository: ${ALEXBELGIUM_REPO}"
  supervisor_api_with_body POST "/store/repositories" \
    "{\"repository\":\"${ALEXBELGIUM_REPO}\"}" > /dev/null

  # Wait for the store to refresh by checking if the postgres addon is available
  log "Waiting for store to refresh..."
  local max_attempts=60
  local attempt=0
  while [ "$attempt" -lt "$max_attempts" ]; do
    if supervisor_api_jq_test "/addons/${POSTGRES_SLUG}/info" '.data.name'; then
      ok "Store refreshed successfully"
      return 0
    fi
    sleep 5
    attempt=$((attempt + 1))
  done
  err "Store did not refresh in time - postgres addon not found"
}

# --- Step 3: Install PostgreSQL ---

install_postgres() {
  local postgres_slug="$1"

  log "Checking PostgreSQL addon status (${postgres_slug})..."
  local version
  version=$(supervisor_api_jq "/addons/${postgres_slug}/info" '.data.version // empty')

  if [ -n "$version" ]; then
    local state
    state=$(supervisor_api_jq "/addons/${postgres_slug}/info" '.data.state')
    ok "PostgreSQL addon already installed (version: ${version}, state: ${state})"
    return 0
  fi

  log "Installing PostgreSQL addon..."
  supervisor_api POST "/addons/${postgres_slug}/install" > /dev/null

  # Wait for installation to complete
  log "Waiting for PostgreSQL installation..."
  local max_attempts=120
  local attempt=0
  while [ "$attempt" -lt "$max_attempts" ]; do
    version=$(supervisor_api_jq "/addons/${postgres_slug}/info" '.data.version // empty')
    if [ -n "$version" ]; then
      ok "PostgreSQL addon installed (version: ${version})"
      return 0
    fi
    sleep 5
    attempt=$((attempt + 1))
  done
  err "PostgreSQL addon installation timed out"
}

# --- Step 4: Configure and start PostgreSQL ---

configure_and_start_postgres() {
  local postgres_slug="$1"

  log "Configuring PostgreSQL addon..."
  local options_json
  options_json=$(jq -n \
    --arg pw "$POSTGRES_PASSWORD" \
    --arg db "$POSTGRES_DB" \
    '{options: {POSTGRES_PASSWORD: $pw, POSTGRES_DB: $db, env_vars: []}}')

  supervisor_api_with_body POST "/addons/${postgres_slug}/options" \
    "${options_json}" > /dev/null

  # Check if already running
  local state
  state=$(supervisor_api_jq "/addons/${postgres_slug}/info" '.data.state')

  if [ "$state" = "started" ]; then
    ok "PostgreSQL addon already running"
    return 0
  fi

  log "Starting PostgreSQL addon..."
  supervisor_api POST "/addons/${postgres_slug}/start" > /dev/null

  # Wait for postgres to be ready
  log "Waiting for PostgreSQL to be ready..."
  local max_attempts=60
  local attempt=0
  while [ "$attempt" -lt "$max_attempts" ]; do
    state=$(supervisor_api_jq "/addons/${postgres_slug}/info" '.data.state')
    if [ "$state" = "started" ]; then
      ok "PostgreSQL addon is running"
      wait_for_postgres_ready "$postgres_slug"
      return 0
    fi
    sleep 5
    attempt=$((attempt + 1))
  done
  err "PostgreSQL addon did not start in time"
}

wait_for_postgres_ready() {
  local postgres_slug="$1"
  # Supervisor renamed add-on containers from addon_* to app_*, so try both.
  local containers=("app_${postgres_slug}" "addon_${postgres_slug}")

  log "Waiting for PostgreSQL database to accept connections..."
  local max_attempts=60
  local attempt=0
  local container probe
  while [ "$attempt" -lt "$max_attempts" ]; do
    for container in "${containers[@]}"; do
      if probe=$(docker exec -e "PGPASSWORD=${POSTGRES_PASSWORD}" "$container" \
          psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1" 2>&1); then
        ok "PostgreSQL database is ready"
        return 0
      fi
    done
    sleep 5
    attempt=$((attempt + 1))
  done
  warn "Last psql output: ${probe}"
  dump_addon_logs "$postgres_slug"
  err "PostgreSQL database did not become ready in time"
}

# --- Step 5: Install and configure addon ---

install_addon() {
  log "Checking ${ADDON_NAME} addon status..."
  local version
  version=$(supervisor_api_jq "/addons/${ADDON_SLUG}/info" '.data.version // empty')

  if [ -n "$version" ]; then
    local state
    state=$(supervisor_api_jq "/addons/${ADDON_SLUG}/info" '.data.state')
    ok "${ADDON_NAME} addon already installed (version: ${version}, state: ${state})"
    return 0
  fi

  log "Installing ${ADDON_NAME} addon..."
  supervisor_api POST "/addons/${ADDON_SLUG}/install" > /dev/null

  # Wait for installation to complete (the TeslaMate image is large)
  log "Waiting for ${ADDON_NAME} installation..."
  local max_attempts=120
  local attempt=0
  while [ "$attempt" -lt "$max_attempts" ]; do
    version=$(supervisor_api_jq "/addons/${ADDON_SLUG}/info" '.data.version // empty')
    if [ -n "$version" ]; then
      ok "${ADDON_NAME} addon installed (version: ${version})"
      return 0
    fi
    sleep 5
    attempt=$((attempt + 1))
  done
  err "${ADDON_NAME} addon installation timed out"
}

configure_and_start_addon() {
  local postgres_slug="$1"

  # Derive the postgres hostname from its slug (underscores → hyphens)
  local postgres_host
  postgres_host=$(echo "$postgres_slug" | tr '_' '-')

  log "Configuring ${ADDON_NAME} addon (db host: ${postgres_host})..."
  local current_options overrides options_json
  current_options=$(supervisor_api_jq "/addons/${ADDON_SLUG}/info" '.data.options')
  overrides=$(jq -n \
    --arg user "$POSTGRES_USER" \
    --arg pass "$POSTGRES_PASSWORD" \
    --argjson port "$POSTGRES_PORT" \
    --arg host "$postgres_host" \
    --arg db "$POSTGRES_DB" \
    --arg tz "$TIMEZONE" \
    '{database_user: $user, database_pass: $pass, database_port: $port, database_host: $host, database_name: $db, database_ssl: false, disable_mqtt: true, grafana_import_dashboards: false, timezone: $tz}')
  options_json=$(jq -n --argjson cur "$current_options" --argjson ovr "$overrides" '{options: ($cur + $ovr)}')

  supervisor_api_with_body POST "/addons/${ADDON_SLUG}/options" \
    "${options_json}" > /dev/null

  # Check if already running
  local state
  state=$(supervisor_api_jq "/addons/${ADDON_SLUG}/info" '.data.state')

  if [ "$state" = "started" ]; then
    ok "${ADDON_NAME} addon already running"
    wait_for_addon_ready
    return 0
  fi

  log "Starting ${ADDON_NAME} addon..."
  supervisor_api POST "/addons/${ADDON_SLUG}/start" > /dev/null

  # Wait for addon state to become "started"
  log "Waiting for ${ADDON_NAME} addon to start..."
  local max_attempts=60
  local attempt=0
  while [ "$attempt" -lt "$max_attempts" ]; do
    state=$(supervisor_api_jq "/addons/${ADDON_SLUG}/info" '.data.state')
    if [ "$state" = "started" ]; then
      break
    fi
    sleep 5
    attempt=$((attempt + 1))
  done
  if [ "$state" != "started" ]; then
    dump_addon_logs "${ADDON_SLUG}"
    err "${ADDON_NAME} addon did not start in time (state: ${state})"
  fi

  wait_for_addon_ready
  ok "${ADDON_NAME} addon started and ready"
}

wait_for_addon_ready() {
  log "Waiting for ${ADDON_NAME} to be ready (listening on port ${ADDON_PORT})..."
  local max_attempts=60
  local attempt=0
  while [ "$attempt" -lt "$max_attempts" ]; do
    local logs
    logs=$(supervisor_api GET "/addons/${ADDON_SLUG}/logs" 2>/dev/null || true)
    if echo "$logs" | grep -qF "$ADDON_READY_LOG"; then
      ok "${ADDON_NAME} is ready"
      return 0
    fi
    sleep 5
    attempt=$((attempt + 1))
  done
  dump_addon_logs "${ADDON_SLUG}"
  err "${ADDON_NAME} did not become ready in time (never saw '${ADDON_READY_LOG}' in logs)"
}

# --- Main ---

main() {
  log "Setting up Home Assistant for ${ADDON_NAME} development"
  echo ""

  wait_for_ha
  complete_onboarding
  add_addon_repo

  install_postgres "$POSTGRES_SLUG"
  configure_and_start_postgres "$POSTGRES_SLUG"
  install_addon
  configure_and_start_addon "$POSTGRES_SLUG"

  echo ""
  ok "Setup complete!"
  local host_port
  # Mirrors the appPort list in devcontainer.json.
  case "${HA_URL##*:}" in
    80) host_port=7180 ;;
    *) host_port=7123 ;;
  esac
  log "  Home Assistant: ${HA_URL} (user: ${ADMIN_USER}, pass: ${ADMIN_PASS})"
  log "    from the host: http://localhost:${host_port}"
  log "  PostgreSQL: ${POSTGRES_SLUG} (user: ${POSTGRES_USER}, db: ${POSTGRES_DB})"
  log "  ${ADDON_NAME}: accessible via Home Assistant ingress"
}

main "$@"
