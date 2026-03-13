"""
The Strategist — reasoning agent (graph entry point).

Tools:
  Native:
    - get_market_snapshot: reads OHLCV + odds from invocation_state (invisible to LLM)
  MCP (Phase 2, require docker compose up):
    - Technical Analysis MCP: calculate_rsi, calculate_macd, calculate_bollinger_bands, calculate_vwap
    - Polymarket MCP: get_active_markets, get_market_odds, get_price_history
    - Web Search MCP: search_crypto_news, get_sentiment_summary

  Set USE_MCP=false in .env to fall back to the stub native tool (Phase 1 mode).

Model:
  LOCAL:  Claude via Anthropic API (LiteLLMModel)
  EKS:    LiteLLM gateway -> vLLM (GPU/Inferentia) — only config.py changes
"""
import os

from strands import Agent, tool
from strands.tools.mcp import MCPClient
from mcp.client.sse import sse_client
from strands.models.litellm import LiteLLMModel
from strands.types.tools import ToolContext

from agents.config import (
    POLYMARKET_MCP_URL,
    REASONING_MODEL,
    SEARCH_MCP_URL,
    STRATEGIST_MAX_TOKENS,
    TA_MCP_URL,
    USE_RAG,
    get_model_client_args,
)
from agents.logging_utils import log_line
from agents.models import StrategistDecision
from agents.strategist.prompts import (
    STRATEGIST_SYSTEM_PROMPT,
    STRATEGIST_SYSTEM_PROMPT_RAG,
    STRATEGIST_SYSTEM_PROMPT_STUB,
)


# ── Native tools (always available) ───────────────────────────────────────────

@tool(context=True)
def get_market_snapshot(tool_context: ToolContext) -> str:
    """
    Get the current BTC candle data (OHLCV) and Polymarket odds from the Watchdog.
    Always call this first — it contains the live market snapshot.
    """
    state = tool_context.invocation_state
    ohlcv = state.get("ohlcv", {})
    odds = state.get("polymarket_odds", 1.0)
    return (
        f"=== Market Snapshot ===\n"
        f"Asset    : {state.get('asset', 'BTC')}\n"
        f"Timeframe: {state.get('timeframe', '15min')}\n"
        f"Open  : ${ohlcv.get('open', 0):,.2f}\n"
        f"High  : ${ohlcv.get('high', 0):,.2f}\n"
        f"Low   : ${ohlcv.get('low', 0):,.2f}\n"
        f"Close : ${ohlcv.get('close', 0):,.2f}\n"
        f"Volume: {ohlcv.get('volume', 0):,.0f}\n"
        f"Polymarket Odds : {odds}x\n"
        f"Implied Prob    : {1 / odds:.1%}\n"
        f"Volatility (1h) : {state.get('volatility', 0):.4f}\n"
        f"Trigger         : {state.get('trigger_reason', 'candle_close')}\n"
        f"Timestamp       : {state.get('timestamp', 'N/A')}\n"
    )


@tool(context=True)
def get_historical_context(tool_context: ToolContext, query: str = "") -> str:
    """
    Search historical BTC context, past signal performance, and key price levels.
    Use this when MCP servers are not available (USE_MCP=false).

    Args:
        query: What context you're looking for (e.g., "recent BTC support levels")
    """
    return (
        f"=== Historical Context (stub — run docker compose up for real data) ===\n"
        f"Query: {query}\n\n"
        f"- BTC has been in a consolidation range $82,000-$85,000 for the past 4h\n"
        f"- Volume profile shows strong support at $82,500\n"
        f"- Last 3 signals: 2 GO (both profitable), 1 NO_GO\n"
        f"- No major macro events in the next 2h\n"
    )


# ── Agent factory ──────────────────────────────────────────────────────────────

def build_strategist() -> Agent:
    """
    Build the Strategist agent.

    With USE_MCP=true (default):  connects to the 3 MCP servers via SSE.
    With USE_MCP=false:           falls back to stub native tools (no docker needed).

    Model is configured via config.py — locally uses Anthropic API,
    on EKS uses LiteLLM proxy pointing to vLLM.
    """
    model = LiteLLMModel(
        client_args=get_model_client_args(),
        model_id=REASONING_MODEL,
        params={"max_tokens": STRATEGIST_MAX_TOKENS, "temperature": 0.1},
    )

    use_mcp = os.getenv("USE_MCP", "true").lower() == "true"
    if use_mcp:
        try:
            ta_mcp = MCPClient(lambda: sse_client(url=TA_MCP_URL))
            polymarket_mcp = MCPClient(lambda: sse_client(url=POLYMARKET_MCP_URL))
            search_mcp = MCPClient(lambda: sse_client(url=SEARCH_MCP_URL))

            if USE_RAG:
                from agents.strategist.tools_rag import query_vectordb
                return Agent(
                    name="strategist",
                    model=model,
                    system_prompt=STRATEGIST_SYSTEM_PROMPT_RAG,
                    tools=[get_market_snapshot, query_vectordb, ta_mcp, polymarket_mcp, search_mcp],
                    structured_output_model=StrategistDecision,
                    structured_output_prompt=(
                        "Return only a JSON object that matches StrategistDecision. "
                        "No markdown, no analysis prose, no extra keys. "
                        "Do not emit interim commentary."
                    ),
                )

            return Agent(
                name="strategist",
                model=model,
                system_prompt=STRATEGIST_SYSTEM_PROMPT,
                tools=[get_market_snapshot, ta_mcp, polymarket_mcp, search_mcp],
                structured_output_model=StrategistDecision,
                structured_output_prompt=(
                    "Return only a JSON object that matches StrategistDecision. "
                    "No markdown, no analysis prose, no extra keys. "
                    "Do not emit interim commentary."
                ),
            )
        except Exception as exc:
            log_line("agent", "strategist", f"MCP unavailable ({exc}). Falling back to stub tools.")

    # Phase 1 / no-docker fallback
    return Agent(
        name="strategist",
        model=model,
        system_prompt=STRATEGIST_SYSTEM_PROMPT_STUB,
        tools=[get_market_snapshot, get_historical_context],
        structured_output_model=StrategistDecision,
        structured_output_prompt=(
            "Return only a JSON object that matches StrategistDecision. "
            "No markdown, no analysis prose, no extra keys. "
            "Do not emit interim commentary."
        ),
    )
