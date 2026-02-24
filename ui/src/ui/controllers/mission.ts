import type { GatewayBrowserClient } from "../gateway.ts";
import type { CronJob, CronRunLogEntry, SwarmStatusResult } from "../types.ts";

export type MissionState = {
  client: GatewayBrowserClient | null;
  connected: boolean;
  missionLoading: boolean;
  missionError: string | null;
  missionSwarm: SwarmStatusResult | null;
  missionCronJobs: CronJob[];
  missionRecentRuns: CronRunLogEntry[];
};

function resolveNovaJob(jobs: CronJob[]): CronJob | null {
  const byName = jobs.find((job) => job.name === "nova-orchestrator-loop");
  if (byName) {
    return byName;
  }
  const byAgent = jobs.find((job) => job.agentId?.trim().toLowerCase() === "nova");
  return byAgent ?? jobs[0] ?? null;
}

export async function loadMission(state: MissionState) {
  if (!state.client || !state.connected || state.missionLoading) {
    return;
  }
  state.missionLoading = true;
  state.missionError = null;
  try {
    const [swarmRes, cronRes] = await Promise.all([
      state.client.request<SwarmStatusResult>("swarm.status", {}),
      state.client.request<{ jobs?: CronJob[] }>("cron.list", {
        includeDisabled: true,
        limit: 50,
        offset: 0,
        sortBy: "updatedAtMs",
        sortDir: "desc",
      }),
    ]);
    const cronJobs = Array.isArray(cronRes.jobs) ? cronRes.jobs : [];
    const novaJob = resolveNovaJob(cronJobs);
    const runsRes = novaJob
      ? await state.client.request<{ entries?: CronRunLogEntry[] }>("cron.runs", {
          id: novaJob.id,
          limit: 20,
        })
      : null;

    state.missionSwarm = swarmRes;
    state.missionCronJobs = cronJobs;
    state.missionRecentRuns = Array.isArray(runsRes?.entries) ? runsRes.entries : [];
  } catch (err) {
    state.missionError = String(err);
  } finally {
    state.missionLoading = false;
  }
}
