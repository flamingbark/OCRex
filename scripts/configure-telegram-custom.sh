#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env.custom"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${OPENCLAW_PROFILE:?OPENCLAW_PROFILE is required}"
: "${TELEGRAM_BOT_TOKEN:?Set TELEGRAM_BOT_TOKEN in .env.custom first}"

# Ensure gateway daemon is running for this profile.
pnpm openclaw --profile "$OPENCLAW_PROFILE" gateway start >/dev/null

# Telegram is a bundled plugin and can be disabled by default.
# Ensure it is enabled before attempting channel setup.
pnpm openclaw --profile "$OPENCLAW_PROFILE" config set plugins.entries.telegram.enabled true --strict-json >/dev/null
pnpm openclaw --profile "$OPENCLAW_PROFILE" gateway restart >/dev/null

# Add/update Telegram account.
pnpm openclaw --profile "$OPENCLAW_PROFILE" channels add \
  --channel telegram \
  --token "$TELEGRAM_BOT_TOKEN"

echo
echo "Telegram channel configured for profile '$OPENCLAW_PROFILE'."
echo "Next steps:"
echo "1) In Telegram, open your bot and send /start."
echo "2) Check status: pnpm openclaw --profile $OPENCLAW_PROFILE channels status --probe"
echo "3) If DM pairing is enabled, approve code: pnpm openclaw --profile $OPENCLAW_PROFILE pairing approve telegram <code>"
