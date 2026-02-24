#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNS_DIR="${RUNS_DIR:-$HOME/.openclaw/cron/runs}"
STATE_DIR="${STATE_DIR:-$HOME/.openclaw-swarm}"
STATE_FILE="$STATE_DIR/provider-fallback-state.json"
PROVIDER_MODE_SCRIPT="$ROOT_DIR/scripts/swarm/provider-mode.sh"

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

if [[ ! -d "$RUNS_DIR" || ! -x "$PROVIDER_MODE_SCRIPT" ]]; then
  exit 0
fi

mkdir -p "$STATE_DIR"
if [[ ! -f "$STATE_FILE" ]]; then
  jq -n '{lastSwitchAt:null,lastRunFingerprint:null}' >"$STATE_FILE"
fi

latest_line="$(
  find "$RUNS_DIR" -maxdepth 1 -type f -name '*.jsonl' -print0 \
    | xargs -0 -r tail -n 1 2>/dev/null \
    | tail -n 1
)"

if [[ -z "$latest_line" ]]; then
  exit 0
fi

if ! jq -e . >/dev/null 2>&1 <<<"$latest_line"; then
  exit 0
fi

fingerprint="$(jq -r '.ts // 0 | tostring' <<<"$latest_line")"
last_fingerprint="$(jq -r '.lastRunFingerprint // ""' "$STATE_FILE")"
if [[ "$fingerprint" == "$last_fingerprint" ]]; then
  exit 0
fi

provider="$(jq -r '.provider // ""' <<<"$latest_line" | tr '[:upper:]' '[:lower:]')"
error_text="$(jq -r '.error // ""' <<<"$latest_line" | tr '[:upper:]' '[:lower:]')"

is_codex_provider=0
if [[ "$provider" == "openai-codex" || "$provider" == "codex" || "$provider" == "openai" ]]; then
  is_codex_provider=1
fi

quota_like=0
if grep -Eq 'insufficient_quota|quota|credit|billing|rate limit|429' <<<"$error_text"; then
  quota_like=1
fi

if [[ "$is_codex_provider" -eq 1 && "$quota_like" -eq 1 ]]; then
  "$PROVIDER_MODE_SCRIPT" openrouter >/dev/null
  jq \
    --arg now "$(date -Is)" \
    --arg fp "$fingerprint" \
    '.lastSwitchAt = $now | .lastRunFingerprint = $fp' \
    "$STATE_FILE" >"$STATE_FILE.tmp"
  mv "$STATE_FILE.tmp" "$STATE_FILE"
  exit 0
fi

jq \
  --arg fp "$fingerprint" \
  '.lastRunFingerprint = $fp' \
  "$STATE_FILE" >"$STATE_FILE.tmp"
mv "$STATE_FILE.tmp" "$STATE_FILE"
