#!/usr/bin/env bash
# run-integration-test.sh - Boot the Supervisor and run setup-ha.sh against it.
#
# Usage: bash .devcontainer/run-integration-test.sh [channel]
#
# The channel (stable, beta or dev) selects which Home Assistant release the
# Supervisor installs. It defaults to stable so that CI tests what users actually
# run; the devcontainer image itself defaults to dev, which means unreleased
# Home Assistant changes would otherwise land straight in CI.
#
# Set DEBUG=1 to stream the Supervisor log instead of capturing it.

set -euo pipefail

export SUPERVISOR_CHANNEL="${1:-stable}"
SUPERVISOR_LOG="/tmp/supervisor.log"

bash .devcontainer/prepare-local-addon.sh

# The v6 devcontainer exposes host AppArmor through OS Agent, but profiles
# applied to containers in its nested Docker daemon break the PostgreSQL image.
sudo systemctl stop haos-agent

# supervisor_run hardcodes SUPERVISOR_DEV=1, which makes the Supervisor force its
# update channel to dev and so install nightly Home Assistant builds whatever
# channel is asked for.
sudo sed -i '/-e SUPERVISOR_DEV=1/d' /usr/bin/supervisor_run

# The channel is otherwise only reachable through the Supervisor API, by which
# point it has already installed Home Assistant, so seed it before first boot.
sudo mkdir -p /mnt/supervisor
printf '{"channel": "%s"}\n' "${SUPERVISOR_CHANNEL}" | sudo tee /mnt/supervisor/updater.json > /dev/null

echo "Home Assistant channel: ${SUPERVISOR_CHANNEL}"

if [ -n "${DEBUG:-}" ]; then
  supervisor_run 2>&1 | tee "${SUPERVISOR_LOG}" &
else
  supervisor_run > "${SUPERVISOR_LOG}" 2>&1 &
fi

if ! bash .devcontainer/setup-ha.sh; then
  echo "::group::Supervisor log (last 300 lines, image pull progress omitted)"
  grep -v -E "docker_image_pull_update|pull_progress" "${SUPERVISOR_LOG}" | tail -n 300
  echo "::endgroup::"
  exit 1
fi
