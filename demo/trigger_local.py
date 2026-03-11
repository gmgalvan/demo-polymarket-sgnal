"""
Manual graph trigger — local test without Watchdog or WebSockets.

Usage:
    python demo/trigger_local.py
    python demo/trigger_local.py --scenario bearish
    python demo/trigger_local.py --scenario no_go
"""
import argparse
import asyncio
from datetime import datetime, timezone

from agents.graph import build_graph

# ── Test scenarios ─────────────────────────────────────────────────────────────

SCENARIOS = {
    "bullish": {
        "description": "BTC oversold, bullish MACD crossover — expecting GO + BUY",
        "invocation_state": {
            "asset": "BTC",
            "timeframe": "15min",
            "ohlcv": {
                "open": 83200.0,
                "high": 83450.0,
                "low": 82800.0,
                "close": 82950.0,
                "volume": 1240.5,
            },
            "polymarket_odds": 1.68,        # implies 59.5% probability
            "volatility": 0.0023,
            "trigger_reason": "candle_close",
            "bankroll": 1000.0,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    },
    "bearish": {
        "description": "BTC overbought, bearish divergence — expecting GO + SELL",
        "invocation_state": {
            "asset": "BTC",
            "timeframe": "15min",
            "ohlcv": {
                "open": 85100.0,
                "high": 85800.0,
                "low": 84900.0,
                "close": 85600.0,
                "volume": 2100.0,
            },
            "polymarket_odds": 2.10,        # implies 47.6% probability
            "volatility": 0.0041,
            "trigger_reason": "volatility_spike",
            "bankroll": 1000.0,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    },
    "no_go": {
        "description": "Sideways market, no clear signal — expecting NO_GO",
        "invocation_state": {
            "asset": "BTC",
            "timeframe": "15min",
            "ohlcv": {
                "open": 84000.0,
                "high": 84150.0,
                "low": 83850.0,
                "close": 84020.0,
                "volume": 420.0,   # very low volume
            },
            "polymarket_odds": 2.00,        # implies 50% probability — no edge
            "volatility": 0.0008,
            "trigger_reason": "candle_close",
            "bankroll": 1000.0,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    },
}


def main():
    parser = argparse.ArgumentParser(description="Trigger the signal graph locally")
    parser.add_argument(
        "--scenario",
        choices=list(SCENARIOS.keys()),
        default="bullish",
        help="Test scenario to run",
    )
    args = parser.parse_args()

    scenario = SCENARIOS[args.scenario]
    print(f"\nScenario: {args.scenario.upper()}")
    print(f"  {scenario['description']}\n")

    graph = build_graph()

    result = asyncio.run(graph.invoke_async(
        "Analyze the current BTC 15min candle and determine if there is a positive EV opportunity. "
        "Use get_market_snapshot and get_historical_context before deciding.",
        invocation_state=scenario["invocation_state"],
    ))

    print(f"\n── Graph result ─────────────────────────────────────")
    print(f"  Status         : {result.status}")
    print(f"  Nodes executed : {result.completed_nodes}/{result.total_nodes}")
    print(f"  Total time     : {result.execution_time}ms")
    if hasattr(result, "accumulated_usage") and result.accumulated_usage:
        print(f"  Tokens used    : {result.accumulated_usage}")
    print(f"─────────────────────────────────────────────────────\n")


if __name__ == "__main__":
    main()
