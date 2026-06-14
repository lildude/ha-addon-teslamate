#!/usr/bin/env bash
# setup-ha.sh - Idempotent Home Assistant setup for TeslaMate development
#
# This script:
# 1. Completes HA onboarding (creates admin user)
# 2. Adds the alexbelgium addon repository (for PostgreSQL)
# 3. Installs and starts PostgreSQL 17
# 4. Installs, configures, and starts the local TeslaMate addon
#
# MQTT and Grafana dashboard import are disabled so TeslaMate boots cleanly
# against PostgreSQL alone. Enable them in the addon configuration once a
# broker / Grafana instance is available.
#
# Usage: bash .devcontainer/setup-ha.sh
#
# Safe to run multiple times (idempotent).

set -euo pipefail

HA_URL="http://localhost:8123"
ALEXBELGIUM_REPO="https://github.com/alexbelgium/hassio-addons"
ADMIN_USER="admin"
ADMIN_PASS="pass"
CLIENT_ID="${HA_URL}/"

POSTGRES_PASSWORD="homeassistant"
POSTGRES_USER="postgres"
POSTGRES_DB="teslamate"
POSTGRES_PORT=5432
# Addon slug = repo_hash + "_" + addon_slug_from_config
# Repo hash: first 8 chars of sha1("https://github.com/alexbelgium/hassio-addons")
POSTGRES_SLUG="db21ed7f_postgres_latest"

TESLAMATE_SLUG="local_teslamate"
TESLAMATE_PORT=4000
TIMEZONE="Europe/London"

# Path to the addon's config.json (one level up from this script's directory),
# resolved independently of the current working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDON_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_JSON="${ADDON_DIR}/config.json"

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

# Query a specific jq field from a Supervisor API response
# Runs curl and jq inside hassio_cli to avoid docker exec stdout pipe issues
supervisor_api_jq() {
  local endpoint="$1" jq_filter="$2"
  docker exec -e "JQ_FILTER=${jq_filter}" hassio_cli sh -c \
    'curl -s -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor'"${endpoint}"' | jq -r "$JQ_FILTER"'
}

# Check if a jq expression matches (returns 0 if match found, 1 otherwise)
supervisor_api_jq_test() {
  local endpoint="$1" jq_filter="$2"
  docker exec -e "JQ_FILTER=${jq_filter}" hassio_cli sh -c \
    'curl -s -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor'"${endpoint}"' | jq -e "$JQ_FILTER" > /dev/null 2>&1'
}

# --- Step 0: Wait for HA to be ready ---

wait_for_ha() {
  log "Waiting for Home Assistant to be ready..."
  local max_attempts=60
  local attempt=0
  while [ "$attempt" -lt "$max_attempts" ]; do
    if curl -sf "${HA_URL}/api/onboarding" > /dev/null 2>&1; then
      ok "Home Assistant is ready"
      return 0
    fi
    sleep 5
    attempt=$((attempt + 1))
  done
  err "Home Assistant did not become ready in time"
}

# --- Step 1: Complete onboarding ---

complete_onboarding() {
  log "Checking onboarding status..."
  local onboarding
  onboarding=$(curl -sf "${HA_URL}/api/onboarding")

  local user_done
  user_done=$(echo "$onboarding" | jq -r '.[] | select(.step == "user") | .done')

  if [ "$user_done" = "true" ]; then
    ok "Onboarding already completed"
    return 0
  fi

  log "Creating admin user '${ADMIN_USER}'..."
  local auth_response
  auth_response=$(curl -sf -X POST "${HA_URL}/api/onboarding/users" \
    -H "Content-Type: application/json" \
    -d "{\"client_id\":\"${CLIENT_ID}\",\"name\":\"Admin\",\"username\":\"${ADMIN_USER}\",\"password\":\"${ADMIN_PASS}\",\"language\":\"en\"}")

  local auth_code
  auth_code=$(echo "$auth_response" | jq -r '.auth_code')

  if [ -z "$auth_code" ] || [ "$auth_code" = "null" ]; then
    err "Failed to create user: ${auth_response}"
  fi

  # Exchange auth code for access token
  local token_response
  token_response=$(curl -sf -X POST "${HA_URL}/auth/token" \
    --data-urlencode "grant_type=authorization_code" \
    --data-urlencode "code=${auth_code}" \
    --data-urlencode "client_id=${CLIENT_ID}")

  local access_token
  access_token=$(echo "$token_response" | jq -r '.access_token')

  if [ -z "$access_token" ] || [ "$access_token" = "null" ]; then
    err "Failed to get access token: ${token_response}"
  fi

  # Complete remaining onboarding steps
  log "Completing onboarding steps..."
  curl -sf -X POST "${HA_URL}/api/onboarding/core_config" \
    -H "Authorization: Bearer ${access_token}" \
    -H "Content-Type: application/json" \
    -d "{}" > /dev/null 2>&1 || true

  curl -sf -X POST "${HA_URL}/api/onboarding/analytics" \
    -H "Authorization: Bearer ${access_token}" \
    -H "Content-Type: application/json" \
    -d "{}" > /dev/null 2>&1 || true

  curl -sf -X POST "${HA_URL}/api/onboarding/integration" \
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
      # Give postgres time to initialize the database
      sleep 10
      return 0
    fi
    sleep 5
    attempt=$((attempt + 1))
  done
  err "PostgreSQL addon did not start in time"
}

# --- Step 5: Install and configure TeslaMate ---

# Remove the "image" key from config.json so the Supervisor builds the addon
# image locally from the Dockerfile instead of pulling a pre-built image.
remove_addon_image() {
  log "Ensuring TeslaMate addon builds locally..."

  if [ ! -f "$CONFIG_JSON" ]; then
    warn "config.json not found at ${CONFIG_JSON} - skipping image removal"
    return 0
  fi

  if ! jq -e 'has("image")' "$CONFIG_JSON" > /dev/null 2>&1; then
    ok "config.json already has no 'image' key - addon will build locally"
    return 0
  fi

  jq 'del(.image)' "$CONFIG_JSON" > "${CONFIG_JSON}.tmp" && mv "${CONFIG_JSON}.tmp" "$CONFIG_JSON"
  ok "Removed 'image' key from config.json"

  # Reload the store so the Supervisor re-reads the local addon config
  log "Reloading addon store..."
  supervisor_api POST "/store/reload" > /dev/null
}

install_teslamate() {
  log "Checking TeslaMate addon status..."
  local version
  version=$(supervisor_api_jq "/addons/${TESLAMATE_SLUG}/info" '.data.version // empty')

  if [ -n "$version" ]; then
    local state
    state=$(supervisor_api_jq "/addons/${TESLAMATE_SLUG}/info" '.data.state')
    ok "TeslaMate addon already installed (version: ${version}, state: ${state})"
    return 0
  fi

  log "Installing TeslaMate addon..."
  supervisor_api POST "/addons/${TESLAMATE_SLUG}/install" > /dev/null

  # Wait for installation to complete (the TeslaMate image is large)
  log "Waiting for TeslaMate installation..."
  local max_attempts=120
  local attempt=0
  while [ "$attempt" -lt "$max_attempts" ]; do
    version=$(supervisor_api_jq "/addons/${TESLAMATE_SLUG}/info" '.data.version // empty')
    if [ -n "$version" ]; then
      ok "TeslaMate addon installed (version: ${version})"
      return 0
    fi
    sleep 5
    attempt=$((attempt + 1))
  done
  err "TeslaMate addon installation timed out"
}

configure_and_start_teslamate() {
  local postgres_slug="$1"

  # Derive the postgres hostname from its slug (underscores -> hyphens)
  local postgres_host
  postgres_host=$(echo "$postgres_slug" | tr '_' '-')

  log "Configuring TeslaMate addon (db host: ${postgres_host})..."

  # Fetch the addon's current options - already populated with defaults - and overlay only
  # the values we need to change.
  local current_options overrides options_json
  current_options=$(supervisor_api_jq "/addons/${TESLAMATE_SLUG}/info" '.data.options')
  overrides=$(jq -n \
    --arg user "$POSTGRES_USER" \
    --arg pass "$POSTGRES_PASSWORD" \
    --argjson port "$POSTGRES_PORT" \
    --arg host "$postgres_host" \
    --arg db "$POSTGRES_DB" \
    --arg tz "$TIMEZONE" \
    '{database_user: $user, database_pass: $pass, database_port: $port, database_host: $host, database_name: $db, database_ssl: false, disable_mqtt: true, grafana_import_dashboards: false, timezone: $tz}')
  options_json=$(jq -n --argjson cur "$current_options" --argjson ovr "$overrides" '{options: ($cur + $ovr)}')

  local response
  response=$(supervisor_api_with_body POST "/addons/${TESLAMATE_SLUG}/options" "${options_json}")
  if [ "$(echo "$response" | jq -r '.result')" != "ok" ]; then
    err "Failed to set TeslaMate options: $(echo "$response" | jq -r '.message // .')"
  fi

  # Check if already running
  local state
  state=$(supervisor_api_jq "/addons/${TESLAMATE_SLUG}/info" '.data.state')

  if [ "$state" = "started" ]; then
    ok "TeslaMate addon already running"
    wait_for_teslamate_ready
    return 0
  fi

  log "Starting TeslaMate addon..."
  supervisor_api POST "/addons/${TESLAMATE_SLUG}/start" > /dev/null

  # Wait for addon state to become "started"
  log "Waiting for TeslaMate addon to start..."
  local max_attempts=60
  local attempt=0
  while [ "$attempt" -lt "$max_attempts" ]; do
    state=$(supervisor_api_jq "/addons/${TESLAMATE_SLUG}/info" '.data.state')
    if [ "$state" = "started" ]; then
      break
    fi
    sleep 5
    attempt=$((attempt + 1))
  done
  if [ "$state" != "started" ]; then
    err "TeslaMate addon did not start in time (state: ${state})"
  fi

  wait_for_teslamate_ready
  ok "TeslaMate addon started and ready"
}

wait_for_teslamate_ready() {
  log "Waiting for TeslaMate to be ready (listening on port ${TESLAMATE_PORT})..."
  local max_attempts=60
  local attempt=0
  while [ "$attempt" -lt "$max_attempts" ]; do
    local logs
    logs=$(supervisor_api GET "/addons/${TESLAMATE_SLUG}/logs" 2>/dev/null || true)
    if echo "$logs" | grep -q "TeslaMateWeb.Endpoint"; then
      ok "TeslaMate is ready"
      return 0
    fi
    sleep 5
    attempt=$((attempt + 1))
  done
  err "TeslaMate did not become ready in time (never saw 'TeslaMateWeb.Endpoint' in logs)"
}

# --- Main ---

main() {
  log "Setting up Home Assistant for TeslaMate development"
  echo ""

  wait_for_ha
  complete_onboarding
  add_addon_repo

  install_postgres "$POSTGRES_SLUG"
  configure_and_start_postgres "$POSTGRES_SLUG"
  remove_addon_image
  install_teslamate
  configure_and_start_teslamate "$POSTGRES_SLUG"

  echo ""
  ok "Setup complete!"
  log "  Home Assistant: ${HA_URL} (user: ${ADMIN_USER}, pass: ${ADMIN_PASS})"
  log "  PostgreSQL: ${POSTGRES_SLUG} (user: ${POSTGRES_USER}, db: ${POSTGRES_DB})"
  log "  TeslaMate: open the TeslaMate panel via HA ingress (${HA_URL})"
}

main "$@"
