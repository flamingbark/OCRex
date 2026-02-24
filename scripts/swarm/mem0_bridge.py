#!/usr/bin/env python3
"""Minimal Mem0 bridge for swarm memory operations.

Usage:
  python3 scripts/swarm/mem0_bridge.py add --user-id <id> --text <text> [--agent-id <id>] [--run-id <id>] [--metadata-json <json>]
  python3 scripts/swarm/mem0_bridge.py search --user-id <id> --query <query> [--limit <n>] [--agent-id <id>] [--run-id <id>]
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any, Dict


def load_openclaw_config() -> Dict[str, Any]:
    cfg_path = Path(os.environ.get("OPENCLAW_CONFIG_PATH", str(Path.home() / ".openclaw" / "openclaw.json")))
    if not cfg_path.exists():
        return {}
    try:
        return json.loads(cfg_path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def strip_openrouter_prefix(model: str) -> str:
    if model.startswith("openrouter/"):
        return model[len("openrouter/") :]
    return model


def resolve_mem0() -> Any:
    try:
        from mem0 import Memory  # type: ignore
    except Exception as exc:
        raise RuntimeError("mem0 package not installed (pip install mem0ai)") from exc

    cfg = load_openclaw_config()
    primary_model = (
        cfg.get("agents", {})
        .get("defaults", {})
        .get("model", {})
        .get("primary", "openrouter/openai/gpt-4o-mini")
    )
    openrouter_key = os.environ.get("OPENROUTER_API_KEY") or cfg.get("env", {}).get("OPENROUTER_API_KEY", "")
    embedding_model = os.environ.get("SWARM_MEM0_EMBEDDING_MODEL", "text-embedding-3-small")
    base_url = os.environ.get("OPENROUTER_API_BASE", "https://openrouter.ai/api/v1")
    if openrouter_key:
        os.environ.setdefault("OPENAI_API_KEY", openrouter_key)
        os.environ.setdefault("OPENAI_BASE_URL", base_url)
    mem0_cfg = {
        "llm": {
            "provider": "openai",
            "config": {
                "model": strip_openrouter_prefix(str(primary_model)),
                "api_key": openrouter_key,
                "base_url": base_url,
            },
        },
        "embedder": {
            "provider": "openai",
            "config": {
                "model": embedding_model,
                "api_key": openrouter_key,
                "base_url": base_url,
            },
        },
        "version": "v1.1",
    }
    try:
        return Memory.from_config(config_dict=mem0_cfg)
    except Exception:
        # Fall back to default constructor when provider override is unsupported.
        return Memory()


def add_memory(args: argparse.Namespace) -> int:
    memory = resolve_mem0()
    messages = [{"role": "user", "content": args.text}]
    metadata = {}
    if args.metadata_json:
        try:
            metadata = json.loads(args.metadata_json)
        except Exception:
            metadata = {"raw": args.metadata_json}
    result = memory.add(
        messages=messages,
        user_id=args.user_id,
        agent_id=args.agent_id,
        run_id=args.run_id,
        metadata=metadata,
    )
    print(json.dumps(result, ensure_ascii=True))
    return 0


def search_memory(args: argparse.Namespace) -> int:
    memory = resolve_mem0()
    result = memory.search(
        query=args.query,
        user_id=args.user_id,
        agent_id=args.agent_id,
        run_id=args.run_id,
        limit=args.limit,
    )
    print(json.dumps(result, ensure_ascii=True))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Mem0 bridge for swarm scripts")
    sub = parser.add_subparsers(dest="command", required=True)

    add = sub.add_parser("add")
    add.add_argument("--user-id", required=True)
    add.add_argument("--text", required=True)
    add.add_argument("--agent-id")
    add.add_argument("--run-id")
    add.add_argument("--metadata-json")

    search = sub.add_parser("search")
    search.add_argument("--user-id", required=True)
    search.add_argument("--query", required=True)
    search.add_argument("--limit", type=int, default=5)
    search.add_argument("--agent-id")
    search.add_argument("--run-id")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if args.command == "add":
        return add_memory(args)
    if args.command == "search":
        return search_memory(args)
    parser.print_help()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
