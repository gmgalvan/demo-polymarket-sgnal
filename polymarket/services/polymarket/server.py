"""
Polymarket MCP Server.

Calls the Polymarket Gamma API (REST, no auth required) to fetch
active prediction markets and real-time odds for BTC/ETH/SOL.

API base: https://gamma-api.polymarket.com

Run locally:
    python services/polymarket/server.py
"""
import json
import os
import httpx
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("Polymarket MCP Server", host="0.0.0.0", port=8001)

GAMMA_BASE = "https://gamma-api.polymarket.com"
CLOB_BASE = "https://clob.polymarket.com"
_HTTP_TIMEOUT = 10.0

# Keyword map: normalise asset name to search term
_ASSET_KEYWORDS = {
    "BTC": "Bitcoin",
    "ETH": "Ethereum",
    "SOL": "Solana",
}


def _get(url: str, params: dict | None = None) -> dict | list:
    """Synchronous httpx GET with timeout."""
    with httpx.Client(timeout=_HTTP_TIMEOUT) as client:
        resp = client.get(url, params=params)
        resp.raise_for_status()
        return resp.json()


def _parse_odds(outcome_prices_raw: str | list | None) -> float | None:
    """
    Convert outcomePrices to decimal odds for the YES outcome.
    outcomePrices is a JSON string like '[\"0.61\", \"0.39\"]'
    or a list ['0.61', '0.39'].
    Returns decimal odds (e.g. 1.64) or None if unparseable.
    """
    if outcome_prices_raw is None:
        return None
    try:
        if isinstance(outcome_prices_raw, str):
            prices = json.loads(outcome_prices_raw)
        else:
            prices = outcome_prices_raw
        yes_prob = float(prices[0])
        if yes_prob <= 0:
            return None
        return round(1.0 / yes_prob, 4)
    except Exception:
        return None


# ── MCP Tools ─────────────────────────────────────────────────────────────────

@mcp.tool(description="Get active BTC/ETH/SOL prediction markets on Polymarket")
def get_active_markets(asset: str = "BTC", limit: int = 3) -> dict:
    """
    Returns active prediction markets for the given asset.

    Args:
        asset: Crypto asset ticker — "BTC", "ETH", or "SOL" (default "BTC")
        limit: Max number of markets to return (default 3)
    """
    keyword = _ASSET_KEYWORDS.get(asset.upper(), asset)
    try:
        data = _get(
            f"{GAMMA_BASE}/markets",
            params={
                "search": keyword,
                "active": "true",
                "closed": "false",
                "limit": limit,
            },
        )
    except Exception as e:
        return {"error": f"Polymarket API unavailable: {e}", "asset": asset}

    markets = []
    for m in data:
        odds = _parse_odds(m.get("outcomePrices"))
        markets.append({
            "id": m.get("conditionId") or m.get("id", ""),
            "question": m.get("question", ""),
            "odds": odds,
            "volume_usd": round(float(m.get("volume", 0) or 0), 2),
            "end_date": m.get("endDate", ""),
        })

    return {
        "asset": asset,
        "markets": markets,
        "count": len(markets),
    }


@mcp.tool(description="Get current odds for a Polymarket market by condition ID")
def get_market_odds(market_id: str) -> dict:
    """
    Returns current odds, implied probability, and volume for a specific market.

    Args:
        market_id: Polymarket condition ID (from get_active_markets)
    """
    try:
        m = _get(f"{GAMMA_BASE}/markets/{market_id}")
    except Exception as e:
        return {"error": f"Market not found or API unavailable: {e}", "market_id": market_id}

    odds = _parse_odds(m.get("outcomePrices"))
    yes_prob = round(1.0 / odds, 4) if odds else None

    return {
        "market_id": market_id,
        "question": m.get("question", ""),
        "odds": odds,
        "implied_probability": yes_prob,
        "volume_usd": round(float(m.get("volume", 0) or 0), 2),
        "end_date": m.get("endDate", ""),
    }


@mcp.tool(description="Get price/odds history for a Polymarket market token")
def get_price_history(token_id: str, interval: str = "1h", fidelity: int = 60) -> dict:
    """
    Returns historical odds series for the YES token of a market.

    Args:
        token_id: Polymarket token ID (clobTokenIds[0] from market data)
        interval: Time interval — "1h", "6h", "1d", "1w" (default "1h")
        fidelity: Data point granularity in minutes (default 60)
    """
    try:
        data = _get(
            f"{CLOB_BASE}/prices-history",
            params={"market": token_id, "interval": interval, "fidelity": fidelity},
        )
    except Exception as e:
        return {"error": f"CLOB API unavailable: {e}", "token_id": token_id}

    history = data.get("history", [])
    if not history:
        return {"token_id": token_id, "history": [], "count": 0}

    prices = [round(float(p["p"]), 4) for p in history]
    latest_prob = prices[-1]
    latest_odds = round(1.0 / latest_prob, 4) if latest_prob > 0 else None

    return {
        "token_id": token_id,
        "interval": interval,
        "latest_probability": latest_prob,
        "latest_odds": latest_odds,
        "price_range": {"min": min(prices), "max": max(prices)},
        "count": len(prices),
        "history": [{"t": p["t"], "p": round(float(p["p"]), 4)} for p in history[-20:]],
    }


if __name__ == "__main__":
    mcp.run(transport="sse")
