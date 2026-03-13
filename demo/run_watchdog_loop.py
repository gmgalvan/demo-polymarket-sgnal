"""
Run the full loop: Watchdog -> Graph in continuous mode.

Examples:
    python demo/run_watchdog_loop.py --mode mock --max-events 3
    python demo/run_watchdog_loop.py --mode websocket
"""
from __future__ import annotations

import argparse
import asyncio
import os

from agents.graph import build_graph
from agents.logging_utils import log_line
from agents.watchdog import Watchdog, WatchdogConfig, run_watchdog_graph_loop


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run Watchdog + Graph full loop")
    parser.add_argument("--mode", choices=["mock", "websocket"], default="mock")
    parser.add_argument("--max-events", type=int, default=None, help="Stop after N triggers")
    parser.add_argument("--mock-interval", type=float, default=None, help="Seconds between mock triggers")
    parser.add_argument(
        "--use-mcp",
        choices=["true", "false"],
        default=None,
        help="Force USE_MCP for this run (default: read env/.env)",
    )
    return parser.parse_args()


async def _main() -> None:
    args = parse_args()

    if args.use_mcp is not None:
        os.environ["USE_MCP"] = args.use_mcp

    config = WatchdogConfig.from_env()
    config.mode = args.mode
    if args.mock_interval is not None:
        config.mock_interval_seconds = args.mock_interval

    graph = build_graph()
    watchdog = Watchdog(config=config)

    log_line("runner", "watchdog-loop", f"Starting mode={config.mode} max_events={args.max_events}")
    processed = await run_watchdog_graph_loop(graph=graph, watchdog=watchdog, max_events=args.max_events)
    log_line("runner", "watchdog-loop", f"Finished triggers_processed={processed}")


if __name__ == "__main__":
    asyncio.run(_main())
