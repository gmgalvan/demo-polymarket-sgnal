# Running the Demo Locally

Complete reference for executing the agent system locally — commands, arguments, modes, and a step-by-step explanation of what happens at runtime.

---

## Agents and Services Reference

### Agents (Python processes)

| Agent | Class / Type | LLM | Node in Graph | Role |
|-------|-------------|-----|--------------|------|
| **El Vigía** (Watchdog) | Pure `asyncio` | No | Outside graph | Monitors market data (Coinbase by default, Binance optional) + Polymarket WebSockets 24/7. Fires `TriggerEvent` on `candle_close` or `volatility_spike`. |
| **El Estratega** (Strategist) | Strands `Agent` — `entry_point` | Yes — Qwen3-30B / Llama 70B | Node 1/2 | Calls MCP tools, queries vector DB (RAG), reasons about market data, outputs `StrategistDecision` (GO/NO_GO + probability + direction). |
| **El Mensajero** (Broadcaster) | Strands `MultiAgentBase` (FunctionNode) | No | Node 2/2 | Receives GO decision, calculates EV and Kelly fraction, formats signal JSON, emits to EventBridge / Telegram / dashboard. |
| **Analista de Contexto** (Context Analyst) | Strands `Agent` | Yes — Llama 3.1 8B | Background (not in main graph) | Summarizes raw text and upserts structured embeddings into the vector store. Runs from CLI or auto-triggered after GO signals. |

### MCP Servers (Docker containers)

| Service | Port | Docker service name | What it provides |
|---------|------|---------------------|-----------------|
| **Polymarket MCP** | 8001 | `polymarket` | `get_active_markets`, `get_market_snapshot`, `get_price_history` — real-time Polymarket odds and volume |
| **Technical Analysis MCP** | 8002 | `technical-analysis` | `calculate_rsi`, `calculate_macd`, `calculate_bollinger_bands`, `calculate_vwap` — deterministic math, never delegated to the LLM |
| **Web Search MCP** | 8003 | `web-search` | `get_sentiment_summary`, `search_news` — Tavily API queries for recent news and sentiment |
| **ChromaDB** | 8004 | `chromadb` | Vector store for RAG. Used by Context Analyst (write) and Strategist via `query_vectordb` (read). In-process mode is also available for local testing without Docker. |

### Tools available to El Estratega

These are the functions the Strategist LLM can call during a graph invocation:

| Tool | Source | Description |
|------|--------|-------------|
| `get_market_snapshot` | Reads `invocation_state` | Returns OHLCV, Polymarket odds, volatility, timeframe injected by the Watchdog |
| `get_active_markets` | Polymarket MCP | Lists active BTC/ETH/SOL prediction markets with odds |
| `get_price_history` | Polymarket MCP | Historical price data for a given market |
| `calculate_rsi` | Technical Analysis MCP | RSI(14) over price series |
| `calculate_macd` | Technical Analysis MCP | MACD line, signal line, histogram |
| `calculate_bollinger_bands` | Technical Analysis MCP | Upper/mid/lower bands, %B position |
| `get_sentiment_summary` | Web Search MCP | Recent news headlines + sentiment label via Tavily |
| `query_vectordb` | `agents/strategist/tools_rag.py` | Semantic search over ChromaDB — returns top-K past signals and news summaries (only active when `USE_RAG=true`) |
| `StrategistDecision` | Strands structured output | Not a real tool — it's the Pydantic model the Strategist must emit before the graph routes to the next node |

---

## Commands

### `demo/trigger_local.py` — Single-shot graph test

Runs one graph invocation with hardcoded market data. No Watchdog, no WebSockets.

```bash
# Default scenario (bullish)
.venv/bin/python demo/trigger_local.py

# With RAG enabled (Strategist queries ChromaDB before deciding)
USE_RAG=true .venv/bin/python demo/trigger_local.py

# Choose a specific scenario
.venv/bin/python demo/trigger_local.py --scenario bearish
.venv/bin/python demo/trigger_local.py --scenario no_go
```

**Arguments:**

| Argument | Values | Default | Effect |
|----------|--------|---------|--------|
| `--scenario` | `bullish`, `bearish`, `no_go` | `bullish` | Selects hardcoded OHLCV + odds dataset to inject into the graph |

**Env variables:**

| Variable | Effect |
|----------|--------|
| `USE_RAG=true` | Adds `query_vectordb` tool to Strategist — reads from ChromaDB before deciding |
| `USE_MCP=true/false` | Enables/disables MCP servers (polymarket, technical-analysis, web-search) |

**Built-in scenarios:**

| Scenario | BTC Price | Polymarket Odds | Trigger | Expected result |
|----------|-----------|----------------|---------|-----------------|
| `bullish` | $82,950 | 1.68 (59.5% implied) | `candle_close` | GO + UP if edge > 3%, else NO_GO |
| `bearish` | $85,600 | 2.10 (47.6% implied) | `volatility_spike` | GO + DOWN |
| `no_go` | $84,020 | 2.00 (50% implied) | `candle_close` | NO_GO — market sideways, no edge |

---

### `demo/run_watchdog_loop.py` — Continuous Watchdog + Graph loop

Runs the full pipeline: Watchdog listens for events → triggers graph → logs result. Loops until `max_events` or Ctrl+C.

```bash
# Mock mode — deterministic, no external connections
.venv/bin/python demo/run_watchdog_loop.py --mode mock --max-events 3

# Mock mode with RAG and MCP
USE_RAG=true .venv/bin/python demo/run_watchdog_loop.py --mode mock --max-events 5 --use-mcp true

# WebSocket mode — real Coinbase prices + Polymarket odds
USE_RAG=true .venv/bin/python demo/run_watchdog_loop.py --mode websocket

# WebSocket mode, stop after 3 real triggers
USE_RAG=true .venv/bin/python demo/run_watchdog_loop.py --mode websocket --max-events 3

# Force Binance provider (optional fallback)
MARKET_DATA_PROVIDER=binance .venv/bin/python demo/run_watchdog_loop.py --mode websocket --max-events 3
```

**Arguments:**

| Argument | Values | Default | Effect |
|----------|--------|---------|--------|
| `--mode` | `mock`, `websocket` | `mock` | Data source for trigger events |
| `--max-events` | integer | `None` (infinite) | Stop after N graph invocations |
| `--mock-interval` | float (seconds) | `5.0` | Seconds between mock trigger events |
| `--use-mcp` | `true`, `false` | From `.env` | Force-enable or disable MCP tool servers |

**Env variables (websocket mode):**

| Variable | Default | Effect |
|----------|---------|--------|
| `MARKET_DATA_PROVIDER` | `coinbase` | Market feed provider: `coinbase` or `binance` |
| `COINBASE_PRODUCT_ID` | `BTC-USD` | Coinbase product for candles stream |
| `COINBASE_WS_URL` | `wss://advanced-trade-ws.coinbase.com` | Coinbase Advanced Trade WebSocket endpoint |
| `BINANCE_SYMBOL` | `btcusdt` | Binance trading pair to stream |
| `BINANCE_INTERVAL` | `15m` | Candle timeframe (`1m`, `5m`, `15m`, `1h`) |
| `BINANCE_WS_URL` | Auto-built from symbol + interval | Override Binance WebSocket URL (used only when `MARKET_DATA_PROVIDER=binance`) |
| `POLYMARKET_WS_URL` | _(empty)_ | Polymarket WebSocket endpoint. If not set, uses `POLYMARKET_DEFAULT_ODDS`. |
| `POLYMARKET_AUTO_SUBSCRIBE` | `true` | Auto-discover active BTC market from Gamma API and subscribe |
| `POLYMARKET_DEFAULT_ODDS` | `2.0` | Fallback odds when Polymarket WS is unavailable |
| `POLYMARKET_SLUG_PATTERN` | _(empty)_ | Rolling slug discovery pattern (e.g. `btc-updown-15m`). Computes slug `btc-updown-15m-{unix_ts}` aligned to 15min windows and fetches via `/events?slug=`. Auto-computes refresh interval (window × 0.9). |
| `POLYMARKET_MARKET_REFRESH_SECONDS` | `0` (disabled) | Reconnect to Polymarket WS every N seconds. Auto-computed from `POLYMARKET_SLUG_PATTERN` when set. Override to force a specific interval. |
| `VOLATILITY_SPIKE_THRESHOLD` | `0.005` (0.5%) | Trigger a graph run mid-candle if price moves this much |
| `WATCHDOG_RECONNECT_DELAY_SECONDS` | `2` | Seconds to wait before reconnecting a dropped WebSocket |

**Modes explained:**

- **`mock`**: Cycles through two hardcoded states (bullish + volatility spike) at a fixed interval. No network calls to market providers or Polymarket. Deterministic and fast — good for testing the graph without waiting.
- **`websocket`**: Opens a real WebSocket to Coinbase (default) or Binance (optional). Triggers on actual market events via candle updates and volatility spikes.

---

### `agents/context_analyst/ingest_context.py` — Vector DB ingestion CLI

Feeds text into ChromaDB so the Strategist can retrieve it via RAG (`query_vectordb`).

```bash
# Built-in sample data — no API keys needed, good for first test
.venv/bin/python agents/context_analyst/ingest_context.py --sample

# Real BTC news from Tavily (requires TAVILY_API_KEY in .env)
.venv/bin/python agents/context_analyst/ingest_context.py --fetch-news
.venv/bin/python agents/context_analyst/ingest_context.py --fetch-news --asset ETH

# Ingest arbitrary text
.venv/bin/python agents/context_analyst/ingest_context.py \
  --asset BTC --source news --text "BTC broke $85k on heavy volume..."

# Pipe from stdin
echo "BTC holding $82k support..." | .venv/bin/python agents/context_analyst/ingest_context.py
```

**Arguments:**

| Argument | Default | Effect |
|----------|---------|--------|
| `--asset` | `BTC` | Asset tag stored with embedding (`BTC`, `ETH`, `SOL`) |
| `--source` | `manual` | Source label stored with embedding (`news`, `technical`, `signal_log`, `tavily_news`) |
| `--text` | _(empty)_ | Raw text to ingest. If omitted, reads from stdin or prompts interactively. |
| `--sample` | _(flag)_ | Ingests 3 built-in BTC contexts (institutional news, technical setup, past signal log) |
| `--fetch-news` | _(flag)_ | Calls Tavily API to fetch real recent news and ingests. Requires `TAVILY_API_KEY`. |

---

## Execution Flow — Step by Step

This is what happens when you run `USE_RAG=true .venv/bin/python demo/trigger_local.py`:

### Step 1 — Build the graph

`build_graph()` in `agents/graph.py` constructs the Strands Graph:

```
[Entry] Strategist ──(GO?)──► Broadcaster
                  └──(NO_GO)── [end]
```

The Strategist node gets its tool list from config — including `query_vectordb` if `USE_RAG=true`. The Broadcaster is a `FunctionNode`: it runs deterministic Python, no LLM.

### Step 2 — Inject `invocation_state`

The script picks a scenario (e.g., BULLISH) and passes `invocation_state` into `graph.invoke_async(...)`. This dict is invisible to the LLM — it's shared context that tools can read, not part of the conversation.

```python
invocation_state = {
    "asset": "BTC",
    "timeframe": "5min",
    "ohlcv": {"open": 83200.0, "high": 83450.0, "low": 82800.0, "close": 82950.0, "volume": 1240.5},
    "polymarket_odds": 1.68,   # → implied probability 59.5%
    "volatility": 0.0023,
    "trigger_reason": "candle_close",
    "bankroll": 1000.0,
}
```

### Step 3 — Strategist gathers data (Tools #1–#10)

The Strategist LLM receives the task prompt and starts calling tools to collect information:

1. **`get_market_snapshot`** — Reads OHLCV and odds directly from `invocation_state`. No network call.
2. **`query_vectordb`** — Semantic search in ChromaDB. Returns top-3 matching past signals/news. Only active with `USE_RAG=true`. (ONNX warning here is harmless — it's looking for a GPU and doesn't find one on WSL2.)
3. **`get_sentiment_summary`** — Calls Web Search MCP → Tavily → recent headlines for BTC.
4. **`calculate_rsi`** / **`calculate_macd`** / **`calculate_bollinger_bands`** — Calls Technical Analysis MCP. May be called twice if the first attempt uses too few price points.
5. **`get_active_markets`** — Calls Polymarket MCP to fetch live market list + odds.

### Step 4 — Strategist reasons and decides

With all data collected, the LLM writes its analysis and calculates the edge:

```
Edge = My_Probability_Estimate − Implied_Probability_from_Odds

Example:
  My estimate:      62%
  Polymarket odds:  1.68 → implied 59.5%
  Edge:             +2.5%  ← below 3% threshold → NO_GO
```

The Strategist then emits a `StrategistDecision` (Tool #11 in the log — actually structured output):

```json
{
  "decision": "NO_GO",
  "direction": "UP",
  "probability": 0.62,
  "confidence": 0.72,
  "reasoning": "Edge below threshold..."
}
```

### Step 5 — Conditional edge routes the graph

The graph's conditional edge checks `decision.decision`:
- `"GO"` → execute Broadcaster node
- `"NO_GO"` → skip Broadcaster, graph ends

This is why the output shows `Nodes executed: 1/2` when the edge is insufficient — the Strategist ran (node 1), the Broadcaster was skipped (node 2 never executed).

### Step 6 — Broadcaster runs (only on GO)

If the decision is GO, the Broadcaster (FunctionNode, no LLM) runs:

1. Reads `StrategistDecision` — direction, probability, confidence
2. Calculates **Expected Value**: `EV = (probability × win_payout) − (1 − probability)`
3. Calculates **Kelly fraction**: `f = (probability × odds − 1) / (odds − 1)`
4. Applies Kelly cap (typically 25% of Kelly for safety)
5. Formats the signal JSON
6. Emits to configured subscribers (EventBridge → Telegram, dashboard, etc.)

### Step 7 — Auto-ingest (only in loop mode with GO)

When running `run_watchdog_loop.py` with `USE_RAG=true`, every GO signal is automatically summarized by the Context Analyst and upserted into ChromaDB. Future runs of the Strategist will find this entry via `query_vectordb`, building a self-improving memory of setups that fired.

---

## Graph Result Interpretation

```
── Graph result ─────────────────────────────────────
  Status         : Status.COMPLETED
  Nodes executed : 1/2       ← 1 = Strategist only (NO_GO), 2/2 = both ran (GO)
  Total time     : 0ms       ← Graph overhead, not LLM time
  Tokens used    : {'inputTokens': 22348, 'outputTokens': 1823, 'totalTokens': 24171}
─────────────────────────────────────────────────────
```

| `Nodes executed` | Meaning |
|-----------------|---------|
| `1/2` | Strategist returned NO_GO. Broadcaster skipped. No signal emitted. |
| `2/2` | Strategist returned GO. Broadcaster ran. Signal was calculated and emitted. |

---

## Recommended Local Setup (full stack)

```bash
# Terminal A — start MCP services
docker compose up -d

# Terminal B — tail MCP logs
docker compose logs -f polymarket technical-analysis web-search

# Terminal C — ingest context once (only needed first time or when stale)
.venv/bin/python agents/context_analyst/ingest_context.py --sample
# or with real news:
.venv/bin/python agents/context_analyst/ingest_context.py --fetch-news

# Terminal D — run the agent loop
USE_RAG=true .venv/bin/python demo/run_watchdog_loop.py \
  --mode websocket --use-mcp true 2>&1 | tee -a logs/agent-loop.log
```

Filter logs for signal events:

```bash
grep -E "\[Watchdog\]|\[Strategist\]|\[Graph\]|SIGNAL" logs/agent-loop.log
```
