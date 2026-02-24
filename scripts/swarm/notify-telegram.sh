#!/usr/bin/env bash
set -euo pipefail

MESSAGE=""
CHAT_ID="${TELEGRAM_CHAT_ID:-}"
BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
OPENCLAW_CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}"
SESSIONS_STORE_PATH="${OPENCLAW_SESSIONS_STORE_PATH:-$HOME/.openclaw/agents/main/sessions/sessions.json}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_CUSTOM_PATH="${ENV_CUSTOM_PATH:-$ROOT_DIR/.env.custom}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --message) MESSAGE="$2"; shift 2 ;;
    --chat-id) CHAT_ID="$2"; shift 2 ;;
    --token) BOT_TOKEN="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$MESSAGE" ]]; then
  echo "message is required" >&2
  exit 1
fi

if [[ -f "$OPENCLAW_CONFIG_PATH" ]]; then
  if [[ -z "$BOT_TOKEN" ]]; then
    BOT_TOKEN="$(jq -r '
      .channels.telegram.accounts.default.botToken
      // .channels.telegram.botToken
      // .env.TELEGRAM_BOT_TOKEN
      // empty
    ' "$OPENCLAW_CONFIG_PATH" 2>/dev/null || true)"
  fi
  if [[ -z "$CHAT_ID" ]]; then
    CHAT_ID="$(jq -r '
      .env.TELEGRAM_CHAT_ID
      // .env.TELEGRAM_TO
      // .notifications.telegram.chatId
      // empty
    ' "$OPENCLAW_CONFIG_PATH" 2>/dev/null || true)"
  fi
fi

if [[ -f "$ENV_CUSTOM_PATH" ]]; then
  if [[ -z "$BOT_TOKEN" ]]; then
    BOT_TOKEN="$(awk -F= '/^TELEGRAM_BOT_TOKEN=/{sub(/^TELEGRAM_BOT_TOKEN=/,""); print; exit}' "$ENV_CUSTOM_PATH")"
  fi
  if [[ -z "$CHAT_ID" ]]; then
    CHAT_ID="$(awk -F= '/^TELEGRAM_CHAT_ID=/{sub(/^TELEGRAM_CHAT_ID=/,""); print; exit}' "$ENV_CUSTOM_PATH")"
  fi
fi

if [[ -z "$CHAT_ID" && -f "$SESSIONS_STORE_PATH" ]]; then
  CHAT_ID="$(jq -r '
    to_entries
    | map(.value + {__key: .key})
    | map(select((.lastChannel // .channel // "") == "telegram"))
    | sort_by(.updatedAt // 0)
    | reverse
    | .[0] // {}
    | (
        .lastTo
        // .to
        // (
          .__key
          | if test("telegram:(direct|dm):") then
              capture("telegram:(?:direct|dm):(?<id>[^:]+)").id
            else
              ""
            end
        )
      )
    | tostring
    | sub("^telegram:(direct|dm|group):"; "")
    | sub("^telegram:"; "")
  ' "$SESSIONS_STORE_PATH" 2>/dev/null || true)"
fi

if [[ -z "$CHAT_ID" || -z "$BOT_TOKEN" ]]; then
  echo "telegram not configured (need TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID)" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 2
fi

api_url="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"
payload="$(jq -n --arg chat_id "$CHAT_ID" --arg text "$MESSAGE" '{chat_id:$chat_id,text:$text,disable_web_page_preview:true}')"

resp="$(curl -sS -X POST "$api_url" -H "Content-Type: application/json" -d "$payload")"
ok="$(jq -r '.ok // false' <<<"$resp" 2>/dev/null || echo "false")"
if [[ "$ok" != "true" ]]; then
  reason="$(jq -r '.description // "telegram send failed"' <<<"$resp" 2>/dev/null || echo "telegram send failed")"
  echo "$reason" >&2
  exit 1
fi

jq -n --arg status "sent" '{status:$status}'
