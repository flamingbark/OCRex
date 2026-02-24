#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-status}"
CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}"
DEFAULT_CODEX_MODEL="${DEFAULT_CODEX_MODEL:-openai-codex/gpt-5.3-codex}"
DEFAULT_OPENROUTER_MODEL="${DEFAULT_OPENROUTER_MODEL:-openrouter/openai/gpt-4o-mini}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 2
fi

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "config not found: $CONFIG_PATH" >&2
  exit 2
fi

show_status() {
  jq -r '
    .agents.defaults.model as $m
    | ($m.primary // "") as $primary
    | ($m.fallbacks // []) as $fallbacks
    | "primary=\($primary)\nfallbacks=\($fallbacks | join(","))"
  ' "$CONFIG_PATH"
}

ensure_model_object() {
  local tmp
  tmp="$(mktemp)"
  jq '
    .agents = (.agents // {})
    | .agents.defaults = (.agents.defaults // {})
    | .agents.defaults.model = (
        if (.agents.defaults.model | type) == "string" then
          { primary: .agents.defaults.model, fallbacks: [] }
        elif (.agents.defaults.model | type) == "object" then
          .agents.defaults.model
        else
          { primary: "", fallbacks: [] }
        end
      )
  ' "$CONFIG_PATH" >"$tmp"
  mv "$tmp" "$CONFIG_PATH"
}

switch_mode() {
  local next_primary="$1"
  local fallback="$2"
  local tmp
  tmp="$(mktemp)"
  jq \
    --arg primary "$next_primary" \
    --arg fallback "$fallback" \
    '
      .agents.defaults.model.primary = $primary
      | .agents.defaults.model.fallbacks = (
          ((.agents.defaults.model.fallbacks // []) + [$fallback])
          | map(select(type == "string" and length > 0))
          | unique
        )
    ' "$CONFIG_PATH" >"$tmp"
  mv "$tmp" "$CONFIG_PATH"
}

ensure_model_object

case "$MODE" in
  status)
    show_status
    ;;
  codex)
    switch_mode "$DEFAULT_CODEX_MODEL" "$DEFAULT_OPENROUTER_MODEL"
    echo "provider mode set: codex-primary"
    show_status
    ;;
  openrouter)
    switch_mode "$DEFAULT_OPENROUTER_MODEL" "$DEFAULT_CODEX_MODEL"
    echo "provider mode set: openrouter-primary"
    show_status
    ;;
  *)
    cat >&2 <<'EOF'
Usage:
  provider-mode.sh status
  provider-mode.sh codex
  provider-mode.sh openrouter
EOF
    exit 1
    ;;
esac
