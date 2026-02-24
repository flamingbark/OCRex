#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env.custom"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE. Run from repo root after creating it." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${OPENCLAW_PROFILE:?OPENCLAW_PROFILE is required}"
: "${OPENCLAW_GATEWAY_PORT:?OPENCLAW_GATEWAY_PORT is required}"
: "${OPENCLAW_GATEWAY_BIND:?OPENCLAW_GATEWAY_BIND is required}"
: "${OPENCLAW_GATEWAY_TOKEN:?OPENCLAW_GATEWAY_TOKEN is required}"
: "${OPENCLAW_CUSTOM_WORKSPACE:?OPENCLAW_CUSTOM_WORKSPACE is required}"

mkdir -p "$OPENCLAW_CUSTOM_WORKSPACE"

pnpm openclaw --profile "$OPENCLAW_PROFILE" onboard \
  --non-interactive \
  --accept-risk \
  --mode local \
  --auth-choice skip \
  --gateway-auth token \
  --gateway-token "$OPENCLAW_GATEWAY_TOKEN" \
  --gateway-port "$OPENCLAW_GATEWAY_PORT" \
  --gateway-bind "$OPENCLAW_GATEWAY_BIND" \
  --workspace "$OPENCLAW_CUSTOM_WORKSPACE" \
  --skip-channels \
  --skip-skills \
  --skip-ui \
  --skip-health \
  --no-install-daemon

echo "Custom OpenClaw profile configured."
echo "Profile: $OPENCLAW_PROFILE"
echo "Gateway: ws://127.0.0.1:$OPENCLAW_GATEWAY_PORT"
