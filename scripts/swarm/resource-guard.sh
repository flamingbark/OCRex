#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_ROOT="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
SWARM_DIR="$ROOT_DIR/.openclaw-swarm"
REGISTRY_PATH="$SWARM_DIR/active-tasks.json"
EVOLUTION_ARCHIVE="$SWARM_DIR/evolution/archive.jsonl"
OPENCLAW_CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-$STATE_ROOT/openclaw.json}"

MAX_USAGE_PERCENT="${SWARM_RESOURCE_MAX_PERCENT:-}"
CRON_RETENTION_DAYS="${SWARM_CRON_RUN_RETENTION_DAYS:-7}"
LOG_RETENTION_DAYS="${SWARM_LOG_RETENTION_DAYS:-7}"
TMP_RETENTION_DAYS="${SWARM_TMP_RETENTION_DAYS:-2}"
TASK_RETENTION_DAYS="${SWARM_TASK_RETENTION_DAYS:-14}"
EVOLUTION_MAX_LINES="${SWARM_EVOLUTION_MAX_LINES:-5000}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 2
fi

if [[ -z "$MAX_USAGE_PERCENT" && -f "$OPENCLAW_CONFIG_PATH" ]]; then
  MAX_USAGE_PERCENT="$(jq -r '.env.SWARM_RESOURCE_MAX_PERCENT // empty' "$OPENCLAW_CONFIG_PATH" 2>/dev/null || true)"
fi
if [[ ! "$MAX_USAGE_PERCENT" =~ ^[0-9]+$ ]]; then
  MAX_USAGE_PERCENT=75
fi
if (( MAX_USAGE_PERCENT < 50 )); then
  MAX_USAGE_PERCENT=50
fi
if (( MAX_USAGE_PERCENT > 95 )); then
  MAX_USAGE_PERCENT=95
fi

usage_pct_disk() {
  df -P "$ROOT_DIR" | awk 'NR==2 {gsub(/%/, "", $5); print $5+0}'
}

usage_pct_mem() {
  if [[ -r /proc/meminfo ]]; then
    awk '
      /^MemTotal:/ {t=$2}
      /^MemAvailable:/ {a=$2}
      END {
        if (t > 0) {
          u=((t-a)/t)*100;
          printf("%d", u+0.5)
        } else {
          print 0
        }
      }
    ' /proc/meminfo
  elif command -v free >/dev/null 2>&1; then
    free | awk '/^Mem:/ { if ($2>0) printf("%d", (($3/$2)*100)+0.5); else print 0 }'
  else
    echo 0
  fi
}

prune_cron_runs() {
  local runs_dir="$STATE_ROOT/cron/runs"
  [[ -d "$runs_dir" ]] || return 0
  find "$runs_dir" -type f -name '*.jsonl' -mtime "+$CRON_RETENTION_DAYS" -delete 2>/dev/null || true
  find "$runs_dir" -type f -name '*.tmp' -mtime +1 -delete 2>/dev/null || true
}

prune_logs() {
  local logs_dir="$STATE_ROOT/logs"
  [[ -d "$logs_dir" ]] || return 0
  find "$logs_dir" -type f -mtime "+$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
}

prune_tmp() {
  find /tmp -maxdepth 1 -type d \( -name 'openclaw-*' -o -name 'codex-*' -o -name 'tmux-*' \) -mtime "+$TMP_RETENTION_DAYS" -exec rm -rf {} + 2>/dev/null || true
  find /tmp -maxdepth 1 -type f \( -name 'openclaw-*' -o -name 'codex-*' \) -mtime "+$TMP_RETENTION_DAYS" -delete 2>/dev/null || true
}

prune_evolution_archive() {
  [[ -f "$EVOLUTION_ARCHIVE" ]] || return 0
  local lines
  lines="$(wc -l <"$EVOLUTION_ARCHIVE" | tr -d ' ')"
  if [[ "$lines" =~ ^[0-9]+$ ]] && (( lines > EVOLUTION_MAX_LINES )); then
    tail -n "$EVOLUTION_MAX_LINES" "$EVOLUTION_ARCHIVE" >"$EVOLUTION_ARCHIVE.tmp"
    mv "$EVOLUTION_ARCHIVE.tmp" "$EVOLUTION_ARCHIVE"
  fi
}

prune_task_registry() {
  [[ -f "$REGISTRY_PATH" ]] || return 0
  local now
  now="$(date +%s)"
  jq --argjson now "$now" --argjson ttlDays "$TASK_RETENTION_DAYS" '
    .tasks |= (
      (. // [])
      | map(
          if (.status == "done" or .status == "failed") then
            . as $t
            | (
                ($t.completedAt // $t.heartbeatAt // $t.startedAt // null)
                | if type == "string" then (fromdateiso8601? // 0) else 0 end
              ) as $ts
            | if $ts == 0 then
                empty
              else
                if ($now - $ts) > ($ttlDays * 86400) then empty else $t end
              end
          else . end
        )
    )
    | .updatedAt = (now | todateiso8601)
  ' "$REGISTRY_PATH" >"$REGISTRY_PATH.tmp" && mv "$REGISTRY_PATH.tmp" "$REGISTRY_PATH"
}

run_cleanup_pass() {
  prune_cron_runs
  prune_logs
  prune_tmp
  prune_evolution_archive
  prune_task_registry
}

before_disk="$(usage_pct_disk)"
before_mem="$(usage_pct_mem)"
triggered=false
if (( before_disk >= MAX_USAGE_PERCENT || before_mem >= MAX_USAGE_PERCENT )); then
  triggered=true
  run_cleanup_pass
fi

after_disk="$(usage_pct_disk)"
after_mem="$(usage_pct_mem)"
still_above=false
if (( after_disk >= MAX_USAGE_PERCENT || after_mem >= MAX_USAGE_PERCENT )); then
  still_above=true
fi

jq -n \
  --argjson max "$MAX_USAGE_PERCENT" \
  --argjson beforeDisk "$before_disk" \
  --argjson beforeMem "$before_mem" \
  --argjson afterDisk "$after_disk" \
  --argjson afterMem "$after_mem" \
  --argjson triggered "$triggered" \
  --argjson stillAbove "$still_above" \
  '{
    maxPercent:$max,
    before:{diskPercent:$beforeDisk,memoryPercent:$beforeMem},
    after:{diskPercent:$afterDisk,memoryPercent:$afterMem},
    cleanupTriggered:$triggered,
    stillAboveLimit:$stillAbove
  }'
