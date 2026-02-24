import { html, nothing } from "lit";
import { formatRelativeTimestamp } from "../format.ts";
import type { CronJob, CronRunLogEntry, SwarmStatusResult, SwarmTaskEntry } from "../types.ts";

export type MissionProps = {
  loading: boolean;
  error: string | null;
  swarm: SwarmStatusResult | null;
  cronJobs: CronJob[];
  recentRuns: CronRunLogEntry[];
  onRefresh: () => void;
};

function formatStatus(status?: string) {
  if (!status) {
    return "unknown";
  }
  return status.replaceAll("_", " ");
}

function laneTasks(tasks: SwarmTaskEntry[], statuses: string[]) {
  const statusSet = new Set(statuses);
  return tasks.filter((task) => statusSet.has(task.status ?? ""));
}

function renderTaskCard(task: SwarmTaskEntry) {
  const prText = task.pr?.number ? `PR #${task.pr.number}` : "No PR";
  return html`
    <article class="mission-task-card">
      <div class="mission-task-card__head">
        <strong>${task.id}</strong>
        <span class="pill">${formatStatus(task.status)}</span>
      </div>
      <div class="muted">${task.description || "No description"}</div>
      <div class="mission-task-card__meta muted">
        <span>${task.branch || "no branch"}</span>
        <span>${prText}</span>
      </div>
      ${task.note ? html`<div class="callout">${task.note}</div>` : nothing}
    </article>
  `;
}

function renderRunItem(run: CronRunLogEntry) {
  return html`
    <div class="mission-run-item">
      <span class="pill">${run.status ?? "unknown"}</span>
      <span class="mono">${run.durationMs ? `${Math.round(run.durationMs / 1000)}s` : "n/a"}</span>
      <span class="muted">${run.runAtMs ? formatRelativeTimestamp(run.runAtMs) : "n/a"}</span>
      <span class="muted">${run.summary ? run.summary.slice(0, 120) : run.error || "no summary"}</span>
    </div>
  `;
}

export function renderMission(props: MissionProps) {
  const tasks = props.swarm?.tasks ?? [];
  const running = laneTasks(tasks, ["running"]);
  const attention = laneTasks(tasks, ["needs_attention"]);
  const done = laneTasks(tasks, ["done", "failed"]);
  const novaJob = props.cronJobs.find((job) => job.name === "nova-orchestrator-loop");

  return html`
    <section class="grid grid-cols-4 mission-kpis">
      <div class="card stat-card">
        <div class="stat-label">Tracked Tasks</div>
        <div class="stat-value">${props.swarm?.counts.total ?? 0}</div>
      </div>
      <div class="card stat-card">
        <div class="stat-label">Running</div>
        <div class="stat-value ok">${props.swarm?.counts.running ?? 0}</div>
      </div>
      <div class="card stat-card">
        <div class="stat-label">Needs Attention</div>
        <div class="stat-value warn">${props.swarm?.counts.needsAttention ?? 0}</div>
      </div>
      <div class="card stat-card">
        <div class="stat-label">Nova Cron</div>
        <div class="stat-value">${novaJob?.enabled ? "Enabled" : "n/a"}</div>
      </div>
    </section>

    <section class="card mission-header">
      <div>
        <div class="card-title">Nova Command Center</div>
        <div class="card-sub">
          Mission-control view for swarm orchestration, run health, and merge readiness.
        </div>
      </div>
      <div class="row">
        <button class="btn" ?disabled=${props.loading} @click=${() => props.onRefresh()}>
          ${props.loading ? "Refreshing..." : "Refresh"}
        </button>
      </div>
    </section>

    ${props.error ? html`<section class="callout danger">${props.error}</section>` : nothing}

    <section class="grid grid-cols-2 mission-grid">
      <div class="card">
        <div class="card-title">Nova Pipeline</div>
        <div class="card-sub">Most recent orchestrator runs</div>
        <div class="mission-run-list">
          ${
            props.recentRuns.length === 0
              ? html`
                  <div class="muted">No recent runs.</div>
                `
              : props.recentRuns.slice(0, 8).map((run) => renderRunItem(run))
          }
        </div>
      </div>
      <div class="card">
        <div class="card-title">Swarm Registry</div>
        <div class="card-sub mono">${props.swarm?.registryPath ?? "not available"}</div>
        <div class="status-list" style="margin-top: 12px;">
          <div><span>Last update</span><span>${props.swarm?.updatedAt ?? "n/a"}</span></div>
          <div><span>Scheduler mode</span><span>${novaJob?.schedule.kind ?? "n/a"}</span></div>
          <div><span>Last run status</span><span>${novaJob?.state.lastRunStatus ?? "n/a"}</span></div>
          <div><span>Consecutive errors</span><span>${novaJob?.state.consecutiveErrors ?? 0}</span></div>
        </div>
      </div>
    </section>

    <section class="mission-board">
      <div class="card mission-lane">
        <div class="card-title">Running</div>
        <div class="card-sub">${running.length} tasks</div>
        <div class="mission-lane__body">
          ${
            running.length === 0
              ? html`
                  <div class="muted">No running tasks.</div>
                `
              : running.map((task) => renderTaskCard(task))
          }
        </div>
      </div>

      <div class="card mission-lane">
        <div class="card-title">Needs Attention</div>
        <div class="card-sub">${attention.length} tasks</div>
        <div class="mission-lane__body">
          ${
            attention.length === 0
              ? html`
                  <div class="muted">No blocked tasks.</div>
                `
              : attention.map((task) => renderTaskCard(task))
          }
        </div>
      </div>

      <div class="card mission-lane">
        <div class="card-title">Done / Failed</div>
        <div class="card-sub">${done.length} tasks</div>
        <div class="mission-lane__body">
          ${
            done.length === 0
              ? html`
                  <div class="muted">No completed tasks yet.</div>
                `
              : done.map((task) => renderTaskCard(task))
          }
        </div>
      </div>
    </section>
  `;
}
