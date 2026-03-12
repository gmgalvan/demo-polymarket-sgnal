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

### PHASE 4 — RAG + Vector DB + Context Analyst
- [x] `services/vectorstore/base.py` — Abstract `VectorStore` interface (`upsert`, `query`, `delete`)
- [x] `services/vectorstore/chroma.py` — `ChromaVectorStore` (local dev, in-process, no server)
- [x] `services/vectorstore/factory.py` — `get_vector_store()` singleton (VECTOR_BACKEND env var)
- [x] `agents/context_analyst/agent.py` — Context Analyst Strands Agent (FAST_MODEL = Haiku/Llama 3.1 8B); `ingest_context(raw_text, asset, source)` async function
- [x] `agents/strategist/tools_rag.py` — `query_vectordb(query, top_k)` native `@tool` for the Strategist
- [x] Wire `query_vectordb` into `build_strategist()` when `USE_RAG=true`
- [x] `STRATEGIST_SYSTEM_PROMPT_RAG` — updated prompt that requires RAG query before deciding
- [x] `USE_RAG`, `VECTOR_BACKEND`, `CHROMA_PATH` in `config.py` and `.env.example`
- [x] `agents/context_analyst/ingest_context.py` — CLI to run Context Analyst (manual/cron); `--sample` flag for built-in test data
- [x] `chromadb` added to `pyproject.toml`
- [ ] Add `MilvusVectorStore` for EKS (Milvus via Helm)
- [ ] Add `OpenSearchVectorStore` for EKS (OpenSearch Serverless alternative)
- [ ] Config switch parity tests (`top_k` + metadata filters) across backends
- [ ] Background loop for Context Analyst (asyncio task running inside Watchdog, periodic re-ingestion)
- [ ] Tests: RAG retrieval quality, graph integration with/without RAG

Notes:
- Local: `VECTOR_BACKEND=chroma` (default) — ChromaDB PersistentClient, no docker server needed
- EKS: swap to `VECTOR_BACKEND=milvus` or `opensearch` — same agent code, only env var changes
- Embeddings: ChromaDB default (sentence-transformers/all-MiniLM-L6-v2, ~80MB, cached after first run)
- Context Analyst uses FAST_MODEL — locally Claude Haiku, on EKS Llama 3.1 8B via vLLM Inferentia
- Strategist uses REASONING_MODEL — locally Claude Haiku/Sonnet, on EKS Qwen3-30B/Llama 70B

### PHASE 5 — GitOps + ArgoCD (EKS Deploy/Operate Bridge)
- [ ] Define GitOps repo structure (platform, inference, apps) and environment overlays (dev/stage/prod)
- [ ] Bootstrap ArgoCD on EKS with App-of-Apps pattern
- [ ] Create ArgoCD Applications for:
  - [ ] inference backends (vLLM GPU / Inferentia)
  - [ ] model gateway (LiteLLM / Envoy option)
  - [ ] agent stack (Watchdog/Strategist/Broadcaster)
  - [ ] observability stack (Prometheus/Grafana/LangFuse)
- [ ] Configure sync waves and health checks so dependencies deploy in correct order
- [ ] Define rollout/rollback strategy (manual sync, automated rollback criteria, rollback runbook)
- [ ] Enable drift detection and alerting workflow
- [ ] Define ArgoCD Projects/RBAC boundaries for platform vs app teams
- [ ] Add a live-demo flow: commit -> ArgoCD sync -> verify -> rollback

Notes:
- This phase is the SDLC bridge in production terms: code-to-cluster traceability and safe operations.
- Scope is intentionally operational (deploy + operate), not full CI pipeline design.

### PHASE 6 (OPTIONAL) — Vision Power-Up on L40S + Text Lane on inf2
- [ ] Define a mini visual use case for the demo (dashboard/chart screenshot analysis)
- [ ] Add a VLM inference path pinned to L40S for image understanding and anomaly cues
- [ ] Implement anomaly signals from visual input (e.g., abrupt trend shape / dashboard red flags)
- [ ] Keep text-only/batch reasoning lane on inf2 to optimize cost
- [ ] Add simple routing policy:
  - [ ] visual request -> L40S lane
  - [ ] text batch request -> inf2 lane
- [ ] Add side-by-side metrics capture for the optional vision lane (latency/cost impact)
- [ ] Add fallback behavior when the vision lane is unavailable

Notes:
- Optional phase for showcasing real GPU value beyond text-only inference.
- Keep this small: one concrete visual scenario is enough for the talk.

### PHASE 7 — Final Demonstration Readiness (Grand Finale)
- [ ] Freeze demo script with exact command sequence and expected outputs
- [ ] Prepare baseline runbooks:
  - [ ] healthy path (normal request routing)
  - [ ] failover path (`L40S` -> `inf2` and recovery)
  - [ ] rollback path (ArgoCD sync/rollback)
- [ ] Define final scorecard shown on stage:
  - [ ] p95 latency
  - [ ] error rate
  - [ ] throughput/tokens per second
  - [ ] estimated cost trend by backend
- [ ] Record backup video with timestamps matching live-demo steps
- [ ] Dry-run full presentation flow at least twice with timing checks
- [ ] Prepare incident fallback matrix (what to skip if time or systems fail)

Notes:
- This is the final production-style validation phase for the meetup demo.
- Goal: deterministic live execution with measurable outcomes.

### PHASE 8 — Observability Stack (Prometheus + Grafana + DCGM)
- [ ] Deploy Prometheus stack on EKS (Prometheus Operator / kube-prometheus-stack)
- [ ] Deploy Grafana with preconfigured data source and dashboard folder structure
- [ ] Enable Kubernetes core exporters:
  - [ ] kube-state-metrics
  - [ ] node-exporter
  - [ ] cAdvisor/container metrics scraping
- [ ] Enable NVIDIA GPU telemetry:
  - [ ] Deploy `dcgm-exporter` on GPU nodes
  - [ ] Capture GPU utilization, memory usage, temperature, power, ECC/errors
- [ ] Enable Inferentia telemetry:
  - [ ] Expose Neuron runtime/NeuronCore metrics to Prometheus (exporter or scrape endpoint)
  - [ ] Track Neuron utilization, latency contribution, and memory pressure signals
- [ ] Add inference service metrics:
  - [ ] request count, error rate, p95/p99 latency
  - [ ] tokens/sec or throughput proxy
  - [ ] backend route label (`l40s` vs `inf2`)
- [ ] Build Grafana dashboards:
  - [ ] Executive dashboard (SLO + cost trend)
  - [ ] Infra dashboard (GPU vs Inferentia health)
  - [ ] Demo dashboard (live before/after failover)
- [ ] Configure alert rules:
  - [ ] high latency
  - [ ] high error rate
  - [ ] backend unavailable
  - [ ] saturation thresholds (GPU/Neuron)

Notes:
- This phase is mandatory for the talk demo narrative (Ops HUD).
- DCGM (`dcgm-exporter`) is the key metric source for NVIDIA L40S visibility in Grafana.
- Use backend labels to compare `l40s` and `inf2` side-by-side in the same panels.

---

## Design Decisions
- **Local model**: LiteLLM → Anthropic API (`ANTHROPIC_API_KEY`)
- **EKS model**: LiteLLM proxy → vLLM (same API, only `api_base` changes in config.py)
- **`invocation_state`**: carries OHLCV, odds, bankroll — invisible to the LLM
- **Conditional edge**: looks for `"GO"` in Strategist text (simple string check, no LLM)
- **BroadcasterNode**: subclass of `MultiAgentBase`, implements `invoke_async`
- **LiteLLM proxy**: `client_args={"api_base": "...", "use_litellm_proxy": True}` (not top-level `base_url`)
- **GitOps control plane (EKS)**: ArgoCD is the deployment contract and rollback mechanism for runtime changes

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
