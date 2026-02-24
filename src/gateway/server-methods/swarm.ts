import fs from "node:fs/promises";
import path from "node:path";
import { resolveAgentWorkspaceDir, resolveDefaultAgentId } from "../../agents/agent-scope.js";
import { loadConfig } from "../../config/config.js";
import type { GatewayRequestHandlers } from "./types.js";

type SwarmTaskStatus = "running" | "needs_attention" | "done" | "failed" | "unknown";

type SwarmTaskEntry = {
  id: string;
  description?: string;
  branch?: string;
  tmuxSession?: string | null;
  agent?: string;
  status?: SwarmTaskStatus;
  startedAt?: string;
  heartbeatAt?: string;
  completedAt?: string;
  note?: string;
  pr?: {
    number?: number | null;
    state?: string | null;
  };
};

function normalizeTaskStatus(input: unknown): SwarmTaskStatus {
  switch (input) {
    case "running":
    case "needs_attention":
    case "done":
    case "failed":
      return input;
    default:
      return "unknown";
  }
}

type SwarmStatusPayload = {
  enabled: boolean;
  registryPath: string;
  updatedAt: string | null;
  tasks: SwarmTaskEntry[];
  counts: {
    total: number;
    running: number;
    needsAttention: number;
    done: number;
    failed: number;
  };
  error?: string;
};

const SWARM_REGISTRY_RELATIVE_PATH = ".openclaw-swarm/active-tasks.json";

function summarize(tasks: SwarmTaskEntry[]) {
  return {
    total: tasks.length,
    running: tasks.filter((task) => task.status === "running").length,
    needsAttention: tasks.filter((task) => task.status === "needs_attention").length,
    done: tasks.filter((task) => task.status === "done").length,
    failed: tasks.filter((task) => task.status === "failed").length,
  };
}

export const swarmHandlers: GatewayRequestHandlers = {
  "swarm.status": async ({ respond }) => {
    const cfg = loadConfig();
    const defaultAgentId = resolveDefaultAgentId(cfg);
    const workspaceDir = resolveAgentWorkspaceDir(cfg, defaultAgentId);
    const registryPath = path.join(workspaceDir, SWARM_REGISTRY_RELATIVE_PATH);

    try {
      const raw = await fs.readFile(registryPath, "utf8");
      const parsed = JSON.parse(raw) as {
        updatedAt?: unknown;
        tasks?: unknown;
      };
      const tasks = Array.isArray(parsed.tasks)
        ? parsed.tasks
            .filter((entry): entry is SwarmTaskEntry => Boolean(entry && typeof entry === "object"))
            .map((entry) => ({
              ...entry,
              status: normalizeTaskStatus(entry.status),
            }))
        : [];
      const payload: SwarmStatusPayload = {
        enabled: true,
        registryPath,
        updatedAt: typeof parsed.updatedAt === "string" ? parsed.updatedAt : null,
        tasks,
        counts: summarize(tasks),
      };
      respond(true, payload, undefined);
    } catch (err) {
      const payload: SwarmStatusPayload = {
        enabled: false,
        registryPath,
        updatedAt: null,
        tasks: [],
        counts: summarize([]),
        error: String(err),
      };
      respond(true, payload, undefined);
    }
  },
};
