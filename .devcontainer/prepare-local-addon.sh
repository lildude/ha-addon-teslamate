#!/usr/bin/env bash
# Remove an add-on's registry image before the Supervisor starts so it must
# build the current checkout's Dockerfile.

set -euo pipefail

config="${1:-config.json}"

if [ ! -f "$config" ]; then
  echo "ERROR: Add-on config not found: ${config}" >&2
  exit 1
fi

if ! jq empty "$config"; then
  echo "ERROR: Invalid add-on config: ${config}" >&2
  exit 1
fi

if jq -e 'has("image")' "$config" > /dev/null; then
  temporary_config=$(mktemp "${config}.XXXXXX")
  trap 'rm -f "$temporary_config"' EXIT

  jq 'del(.image)' "$config" > "$temporary_config"
  mv "$temporary_config" "$config"
fi

if jq -e 'has("image")' "$config" > /dev/null; then
  echo "ERROR: Failed to remove image from ${config}" >&2
  exit 1
fi

echo "Registry image disabled; the Supervisor will build the current checkout"