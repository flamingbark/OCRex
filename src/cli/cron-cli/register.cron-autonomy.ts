import type { Command } from "commander";
import type { CronJob } from "../../cron/types.js";
import { danger } from "../../globals.js";
import { sanitizeAgentId } from "../../routing/session-key.js";
import { defaultRuntime } from "../../runtime.js";
import type { GatewayRpcOpts } from "../gateway-rpc.js";
import { addGatewayClientOptions, callGatewayFromCli } from "../gateway-rpc.js";
import { parseDurationMs, warnIfCronSchedulerDisabled } from "./shared.js";

type AutonomyCliOpts = GatewayRpcOpts & {
  name?: string;
  description?: string;
  every?: string;
  objective?: string;
  testCommand?: string;
  agent?: string;
  model?: string;
  thinking?: string;
  channel?: string;
  to?: string;
  bestEffortDeliver?: boolean;
  replace?: boolean;
  disabled?: boolean;
  json?: boolean;
};

const DEFAULT_AUTONOMY_JOB_NAME = "openclaw-self-improvement-loop";
const DEFAULT_AUTONOMY_EVERY = "1h";
const DEFAULT_AUTONOMY_TEST_CMD = "pnpm test:fast";

function buildAutonomyPrompt(params: { objective: string; testCommand: string }): string {
  return [
    "You are OpenClaw's autonomous maintenance agent.",
    `Objective: ${params.objective}`,
    "",
    "Run this loop each cycle:",
    "1) Inspect the repository state and recent issues/failures.",
    "2) Pick one high-impact, low-risk improvement and write a short plan.",
    "3) Implement minimal, reversible changes.",
    `4) Run validation: ${params.testCommand}.`,
    "5) If validation fails, iterate until green or revert the unsafe change.",
    "6) Write a concise summary with risks and follow-ups.",
    "",
    "Safety rules:",
    "- Minimize permission requests and keep commands non-interactive.",
    "- Never use destructive git commands (reset --hard, checkout --, force push).",
    "- Prefer small scoped edits and maintain backward compatibility.",
  ].join("\n");
}

export function registerCronAutonomyCommand(cron: Command) {
  addGatewayClientOptions(
    cron
      .command("autonomy")
      .description("Bootstrap an autonomous self-improvement cron loop")
      .option("--name <name>", "Cron job name", DEFAULT_AUTONOMY_JOB_NAME)
      .option("--description <text>", "Optional job description")
      .option("--every <duration>", "Schedule interval (e.g. 15m, 1h, 1d)", DEFAULT_AUTONOMY_EVERY)
      .option(
        "--objective <text>",
        "High-level objective for each run",
        "Improve OpenClaw reliability, correctness, and developer velocity with safe incremental changes.",
      )
      .option(
        "--test-command <cmd>",
        "Validation command run each cycle",
        DEFAULT_AUTONOMY_TEST_CMD,
      )
      .option("--agent <id>", "Agent id for the autonomy job", "main")
      .option("--model <model>", "Model override (provider/model or alias)")
      .option("--thinking <level>", "Thinking level (off|minimal|low|medium|high)", "low")
      .option("--channel <channel>", "Delivery channel for summaries", "last")
      .option("--to <dest>", "Delivery destination for summaries")
      .option("--best-effort-deliver", "Do not fail job when delivery fails", false)
      .option("--replace", "Replace an existing job with the same --name", true)
      .option("--no-replace", "Fail if a job with the same --name already exists")
      .option("--disabled", "Create the job disabled", false)
      .option("--json", "Output JSON", false)
      .action(async (opts: AutonomyCliOpts) => {
        try {
          const nameRaw = typeof opts.name === "string" ? opts.name.trim() : "";
          if (!nameRaw) {
            throw new Error("--name is required");
          }

          const everyRaw =
            typeof opts.every === "string" && opts.every.trim()
              ? opts.every.trim()
              : DEFAULT_AUTONOMY_EVERY;
          const everyMs = parseDurationMs(everyRaw);
          if (!everyMs) {
            throw new Error("Invalid --every; use e.g. 15m, 1h, 1d");
          }

          const objectiveRaw = typeof opts.objective === "string" ? opts.objective.trim() : "";
          if (!objectiveRaw) {
            throw new Error("--objective cannot be empty");
          }
          const testCommand =
            typeof opts.testCommand === "string" && opts.testCommand.trim()
              ? opts.testCommand.trim()
              : DEFAULT_AUTONOMY_TEST_CMD;

          const listRes = (await callGatewayFromCli("cron.list", opts, {
            includeDisabled: true,
          })) as { jobs?: CronJob[] };
          const existing = (listRes.jobs ?? []).filter((job) => job.name === nameRaw);

          if (existing.length > 0 && !opts.replace) {
            throw new Error(
              `Cron job "${nameRaw}" already exists (${existing.length} match${existing.length === 1 ? "" : "es"}). Use --replace to recreate it.`,
            );
          }

          const agentIdRaw = typeof opts.agent === "string" ? opts.agent.trim() : "main";
          const agentId = agentIdRaw ? sanitizeAgentId(agentIdRaw) : "main";
          const prompt = buildAutonomyPrompt({ objective: objectiveRaw, testCommand });

          const desiredSpec = {
            name: nameRaw,
            description:
              typeof opts.description === "string" && opts.description.trim()
                ? opts.description.trim()
                : "Autonomous OpenClaw self-improvement loop",
            enabled: !opts.disabled,
            agentId,
            schedule: { kind: "every" as const, everyMs },
            sessionTarget: "isolated" as const,
            wakeMode: "next-heartbeat" as const,
            payload: {
              kind: "agentTurn" as const,
              message: prompt,
              model:
                typeof opts.model === "string" && opts.model.trim() ? opts.model.trim() : undefined,
              thinking:
                typeof opts.thinking === "string" && opts.thinking.trim()
                  ? opts.thinking.trim()
                  : undefined,
            },
            delivery: {
              mode: "announce" as const,
              channel:
                typeof opts.channel === "string" && opts.channel.trim()
                  ? opts.channel.trim()
                  : "last",
              to: typeof opts.to === "string" && opts.to.trim() ? opts.to.trim() : undefined,
              bestEffort: opts.bestEffortDeliver ? true : undefined,
            },
          };

          // Prefer in-place update when exactly one matching job exists to preserve run history.
          // If multiple stale duplicates exist, remove and recreate to converge to one canonical job.
          const response =
            existing.length === 1 && opts.replace
              ? await callGatewayFromCli("cron.update", opts, {
                  id: existing[0].id,
                  patch: desiredSpec,
                })
              : await (async () => {
                  if (existing.length > 0 && opts.replace) {
                    for (const job of existing) {
                      await callGatewayFromCli("cron.remove", opts, { id: job.id });
                    }
                  }
                  return callGatewayFromCli("cron.add", opts, desiredSpec);
                })();

          if (opts.json) {
            defaultRuntime.log(JSON.stringify(response, null, 2));
          } else {
            defaultRuntime.log(
              `Autonomy loop ready: ${nameRaw} (${everyRaw}, agent=${agentId}, session=isolated)`,
            );
            defaultRuntime.log("Loop behavior: inspect -> plan -> edit -> validate -> summarize.");
          }
          await warnIfCronSchedulerDisabled(opts);
        } catch (err) {
          defaultRuntime.error(danger(String(err)));
          defaultRuntime.exit(1);
        }
      }),
  );
}
