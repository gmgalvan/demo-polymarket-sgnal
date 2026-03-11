# Build Plan — Polymarket Signal Agent (Local Dev)

## Goal
Build and test the agents locally before deploying to EKS.
Local code is identical to production — only model configuration changes.

## Local Stack
- **Model**: Anthropic Claude API (via LiteLLM) → later LiteLLM + vLLM on EKS
- **MCP Servers**: FastMCP running locally (SSE, ports 8001-8003)
- **Vector DB**: ChromaDB local (no server) → later Milvus/Qdrant on EKS
- **Notifications**: Print to console → later Discord/Telegram/EventBridge on EKS
- **Data**: Mock JSON + Polymarket REST API → later WebSockets in production

---

## Phases

### PHASE 1 — Graph core (no MCP, no Watchdog) ← DONE
- [x] `pyproject.toml` + `.env.example`
- [x] `agents/models.py` — Pydantic: StrategistDecision, Signal
- [x] `agents/broadcaster/node.py` — BroadcasterNode (EV/Kelly, no LLM)
- [x] `agents/strategist/prompts.py` — System prompt
- [x] `agents/strategist/agent.py` — Strands Agent + mock tools
- [x] `agents/graph.py` — GraphBuilder: Strategist → Broadcaster
- [x] `agents/config.py` — Settings (model, env vars)
- [x] `demo/trigger_local.py` — Trigger graph with hardcoded data
- [x] `tests/fixtures/sample_candle.py` — Mock OHLCV + odds
- [x] `tests/test_broadcaster.py` — Unit: EV/Kelly math
- [x] `tests/test_graph.py` — E2E basic

### PHASE 2 — MCP Servers ← DONE
- [x] `services/technical_analysis/server.py` — RSI, MACD, Bollinger, VWAP (pure numpy, FastMCP SSE)
- [x] `services/polymarket/server.py` — Polymarket Gamma API (httpx, FastMCP SSE)
- [x] `services/web_search/server.py` — Tavily search (FastMCP SSE)
- [x] Connect MCP servers to the Strategist via MCPClient (USE_MCP=true/false toggle)
- [x] `docker-compose.yml` — Run all 3 MCP servers together
- [x] `tests/test_ta_mcp.py` — 20 unit tests for TA math (no network)

Notes:
- MCPClient import: `from strands.tools.mcp import MCPClient` (not `strands.mcp`)
- SSE client import: `from mcp.client.sse import sse_client` (mcp package, not strands)
- USE_MCP=false disables MCP and uses stub tools (no docker needed)

### PHASE 3 — Watchdog + full loop
- [x] `agents/watchdog/watchdog.py` — asyncio watchdog (mock mode: sleep + static data)
- [x] Connect Watchdog → Graph in a loop
- [x] Real WebSocket mode (Binance + Polymarket)

### PHASE 4 — RAG + Vector DB
- [ ] `services/rag/` — local RAG service with Weaviate integration (open source for dev)
- [ ] `agents/strategist/tools_rag.py` — `query_vectordb(query, top_k)` tool for the Strategist
- [ ] Add RAG toggle in config (`USE_RAG=true/false`) and wire into `build_strategist()`
- [ ] `scripts/ingest_context.py` — ingest historical market context, past signals, and news summaries into vector DB
- [ ] Add `VectorStore` abstraction layer (`upsert`, `query`, `delete`) to avoid vendor lock-in
- [ ] Implement `WeaviateVectorStore` for local development
- [ ] Implement `OpenSearchVectorStore` for AWS deployment
- [ ] Config switch (`VECTOR_BACKEND=weaviate|opensearch`) with same schema/metadata contract
- [ ] Keep embedding model + similarity metric consistent across backends for retrieval parity
- [ ] Update Strategist prompt to require RAG query before final decision
- [ ] Add tests for RAG retrieval quality and graph integration with/without RAG
- [ ] Add backend parity tests (`top_k` + filters) for Weaviate vs OpenSearch
- [ ] Document migration path: local Weaviate → OpenSearch on AWS

---

## Design Decisions
- **Local model**: LiteLLM → Anthropic API (`ANTHROPIC_API_KEY`)
- **EKS model**: LiteLLM proxy → vLLM (same API, only `api_base` changes in config.py)
- **`invocation_state`**: carries OHLCV, odds, bankroll — invisible to the LLM
- **Conditional edge**: looks for `"GO"` in Strategist text (simple string check, no LLM)
- **BroadcasterNode**: subclass of `MultiAgentBase`, implements `invoke_async`
- **LiteLLM proxy**: `client_args={"api_base": "...", "use_litellm_proxy": True}` (not top-level `base_url`)

---

## How to test manually (Phase 1)
```bash
# 1. Install dependencies
pip install -e ".[dev]"

# 2. Set up env
cp .env.example .env
# edit .env with ANTHROPIC_API_KEY

# 3. Unit tests (no API key needed)
pytest tests/test_broadcaster.py -v

# 4. Trigger the graph (uses Claude API)
python demo/trigger_local.py --scenario bullish
python demo/trigger_local.py --scenario bearish
python demo/trigger_local.py --scenario no_go

# 5. E2E test
pytest tests/test_graph.py -v -s -m integration
```

## How to test manually (Phase 3)
```bash
# Mock watchdog loop (no WebSocket/network required)
python demo/run_watchdog_loop.py --mode mock --max-events 3

# Unit tests for watchdog parsing and mock loop
pytest tests/test_watchdog.py -v

# WebSocket mode (requires reachable WS endpoints)
python demo/run_watchdog_loop.py --mode websocket
```

---

## Strands API Notes (verified in docs)
- `GraphBuilder` → `from strands.multiagent import GraphBuilder`
- `GraphState` → `from strands.multiagent.graph import GraphState`
- `MultiAgentBase` → `from strands.multiagent.base import MultiAgentBase`
- `LiteLLMModel` → `client_args={"api_base": url, "api_key": key, "use_litellm_proxy": True}`
- `BroadcasterNode` is not built-in — must subclass `MultiAgentBase`
- `invocation_state` is passed as arg to `invoke_async(task, invocation_state, **kwargs)`
