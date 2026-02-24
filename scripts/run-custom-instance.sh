#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env.custom"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE. Run setup first." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

pnpm openclaw --profile "$OPENCLAW_PROFILE" gateway run \
  --bind "$OPENCLAW_GATEWAY_BIND" \
  --port "$OPENCLAW_GATEWAY_PORT" \
  --token "$OPENCLAW_GATEWAY_TOKEN"
