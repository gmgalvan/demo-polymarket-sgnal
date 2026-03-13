# Components

> **Status: Phases 1–4 implemented locally.** EKS deployment is pending.

## Overview

This document describes each component of the system, its responsibility, where it runs, and how it connects to other components. Components are organized by layer (matching the 3-layer architecture in `architecture.md` and `CLAUDE.md`).

---

## Layer 1: Platform

These components are provisioned once and provide the foundation for everything else.

### EKS Cluster

**What it is:** The Kubernetes control plane managed by AWS.

**Responsibility:** Orchestrates all workloads. Provides the API server, scheduler, etcd, and all core Kubernetes functionality.

**Key configuration:**
- 3 Availability Zones for high availability
- Private subnets for workloads, public subnets for load balancers
- RBAC roles mapped to IAM (Admin, Editor, Reader)

---

### Karpenter (Autoscaler)

**What it is:** An intelligent node provisioner that replaces traditional auto scaling groups.

**Responsibility:** Observes pods that can't be scheduled (pending), analyzes their resource requests, and provisions the optimal instance type. When pods are removed, it consolidates and terminates unnecessary nodes.

**Why it matters for this demo:** It's the mechanism that makes multi-architecture transparent. A pod requesting GPU gets a GPU node. A pod requesting only CPU gets an ARM node. The application doesn't decide — Karpenter does.

**Node Pools:**

| Pool | Instance Families | What Runs Here | Taint |
|------|------------------|---------------|-------|
| ARM cost-optimized | c7g, m7g, r7g (Graviton) | Strands agent, MCP servers, LiteLLM, LangFuse, Prometheus/Grafana | None (default pool) |
| GPU | g5, g6 | vLLM with CUDA | `nvidia.com/gpu=true:NoSchedule` |
| ML Accelerator | inf2 | vLLM with Neuron SDK | `aws.amazon.com/neuron=true:NoSchedule` |

---

### Device Plugins

**What they are:** DaemonSets that register hardware accelerators with the Kubernetes kubelet.

**NVIDIA Device Plugin:**
- Runs on GPU nodes only (via node selector)
- Discovers NVIDIA GPUs on the node
- Registers `nvidia.com/gpu` as an allocatable resource
- Pods request it via `resources.limits.nvidia.com/gpu: 1`

**AWS Neuron Device Plugin:**
- Runs on Inferentia nodes only (via node selector)
- Discovers Neuron cores and devices
- Registers `aws.amazon.com/neuroncore` and `aws.amazon.com/neurondevice`
- Pods request it via `resources.limits.aws.amazon.com/neuroncore: 2`

---

### Observability Stack

**Infrastructure monitoring (Prometheus + Grafana):**
- Prometheus scrapes cluster metrics, vLLM metrics, Karpenter metrics
- Grafana dashboards: GPU utilization, node count per pool, inference latency, pod scheduling times, cost estimates per tier

**Agent tracing (LangFuse):**
- Ingests OpenTelemetry traces emitted automatically by Strands SDK
- Visualizes: full agent interaction chain, every tool call with input/output, token usage per step, reasoning path, latency breakdown
- Enables debugging: "Why did the agent generate this signal? What tools did it call and in what order?"

---

### vLLM (LLM Inference Engine)

**What it is:** A high-performance model serving framework that loads a pre-trained model into GPU/accelerator memory and serves an OpenAI-compatible API.

**Responsibility:** Receive inference requests, batch them efficiently (continuous batching), generate tokens, return responses.

**Model:** Llama 3.1 8B-Instruct (see `docs/models.md` for details).

**Deployments:**

| Deployment | Hardware | Container Image | Resource Request | Endpoint |
|-----------|----------|----------------|-----------------|----------|
| `vllm-gpu` | g5.xlarge (1x A10G, 24GB) | `vllm/vllm-openai:latest` | `nvidia.com/gpu: 1` | `:8000/v1/chat/completions` |
| `vllm-neuron` | inf2.xlarge (2 Neuron cores) | `vllm/vllm-neuron:latest` | `aws.amazon.com/neuroncore: 2` | `:8000/v1/chat/completions` |

**Key point:** Both deployments expose the SAME API. Consumers cannot tell the difference.

---

### LiteLLM (Model Gateway)

**What it is:** A Python-based API gateway that sits in front of all vLLM backends.

**Responsibility:**
- Single endpoint for the Strands agent: `http://litellm-gateway:4000`
- Routes requests to the appropriate vLLM backend
- Failover: if GPU backend is unhealthy, redirect to Neuron (or vice versa)
- Rate limiting per consumer
- Token and cost tracking per request
- Web UI for model management and monitoring

**Where it runs:** ARM node. It's an HTTP proxy — no GPU needed.

**LiteLLM config (simplified):**
```yaml
model_list:
  - model_name: llama-3.1-8b
    litellm_params:
      model: openai/meta-llama/Llama-3.1-8B-Instruct
      api_base: http://vllm-gpu:8000/v1
  - model_name: llama-3.1-8b
    litellm_params:
      model: openai/meta-llama/Llama-3.1-8B-Instruct
      api_base: http://vllm-neuron:8000/v1

router_settings:
  routing_strategy: least-busy
  enable_fallbacks: true
```

Both entries share the same `model_name`. LiteLLM load-balances between them and fails over automatically.

---

## Layer 2: Intelligence (Agent)

### Agent System (Strands Graph)

The agent layer uses the **Strands Graph pattern** with three components. See `docs/agent-patterns.md` for full implementation details.

#### Watchdog (El Vigía)

**What it is:** Pure asyncio Python script — NOT a Strands agent.

**Responsibility:** Monitors Coinbase Advanced Trade WebSocket (BTC 5-minute candles, default) or Binance WebSocket (optional fallback), plus Polymarket WebSocket (odds) 24/7. Fires `graph.invoke_async()` on `candle_close` or `volatility_spike` (intra-candle move ≥ threshold). Passes `invocation_state` with OHLCV + odds + bankroll to the Graph.

**Where it runs:** ARM node. No GPU needed — it's just asyncio WebSocket listeners.

**Uses LLM?** No.

---

#### Strategist (El Estratega) — Graph entry_point

**What it is:** Strands Agent (`name="strategist"`), the reasoning component.

**Responsibility:**
- Calls `get_market_snapshot` (reads `invocation_state` via `tool_context`)
- Calls MCP tools: TA indicators (RSI, MACD, Bollinger), Polymarket market data, web search (news/sentiment)
- Reasons about all data and emits a structured `StrategistDecision` (GO/NO_GO, probability, direction, confidence, reasoning)

**Where it runs:** ARM node (lightweight Python process). LLM inference runs on vLLM via LiteLLM gateway.

**Uses LLM?** Yes — main LLM consumer. Multiple tool calls + final structured output per invocation.

**Model:** Local: Claude via Anthropic API. EKS: Qwen3-30B / Llama 3.1 70B via LiteLLM → vLLM (GPU or Inferentia). Only `config.py` changes.

---

#### Broadcaster (BroadcasterNode) — FunctionNode

**What it is:** Deterministic `MultiAgentBase` subclass — NOT a Strands agent (no LLM).

**Responsibility:**
1. Deserializes `StrategistDecision` from the Graph edge
2. Reads odds + bankroll from `invocation_state`
3. Calculates EV: `ev = prob × (odds−1) − (1−prob)` and Kelly: `kelly = ev / (odds−1)`
4. Formats a `Signal` Pydantic model
5. Emits: `_emit()` → console log locally, EventBridge on EKS

**Where it runs:** ARM node. 100% deterministic — no network calls locally.

**Uses LLM?** No.

**Native tools (`@tool`):** EV/Kelly math lives inside `BroadcasterNode.invoke_async()`, not as standalone `@tool` decorators — it depends on the Strategist's output and runs after the LLM has reasoned.

---

### MCP Server: Polymarket API

**What it is:** A service that wraps the Polymarket API and exposes it as MCP tools.

**Responsibility:** Provide real-time prediction market data to the agent.

**Tools exposed:**
- `get_active_markets(asset, timeframe)` — List active prediction markets for BTC/ETH/SOL
- `get_market_odds(market_id)` — Current odds/probability for a specific market
- `get_market_volume(market_id)` — Trading volume and liquidity
- `get_price_history(asset, timeframe, periods)` — Historical price data for technical analysis

**Where it runs:** ARM node. HTTP service making API calls — no GPU.

**Uses LLM?** No.

**External dependency:** Polymarket REST API (public, no auth required for read).

**Fallback:** Cached responses stored locally in case API is down during demo.

---

### MCP Server: Technical Analysis

**What it is:** A service that computes quantitative trading indicators from price data.

**Responsibility:** Perform mathematical calculations that the LLM cannot reliably do.

**Tools exposed:**
- `calculate_rsi(prices, period)` — Relative Strength Index (overbought/oversold)
- `calculate_macd(prices)` — Moving Average Convergence Divergence (trend direction)
- `calculate_bollinger_bands(prices)` — Price volatility bands (extreme positions)
- `calculate_vwap(prices, volumes)` — Volume-Weighted Average Price
- `generate_ta_summary(asset, timeframe)` — All-in-one: "RSI at 72 (overbought), MACD bearish crossover, price at upper Bollinger Band"

**Where it runs:** ARM node. Uses numpy/pandas — CPU is sufficient.

**Uses LLM?** No.

**Why this matters:** LLMs are notoriously bad at math. Asking an LLM to calculate RSI gives unreliable results. By delegating to a specialized tool, we get precise calculations every time. The LLM's job is to INTERPRET the results, not calculate them.

---

### MCP Server: Web Search

**What it is:** A pre-built web search service optimized for AI agent queries.

**Responsibility:** Search the web for recent news, sentiment, and events that could impact markets.

**Tools exposed:**
- `search(query)` — General web search
- `search_news(query)` — Recent news articles

**Where it runs:** ARM node.

**Uses LLM?** No.

**External dependency:** Tavily API (requires API key, has free tier).

**Why it matters:** Technical indicators only capture price patterns. News like "ETF approved" or "exchange hacked" moves markets independently of technical signals. The agent needs both quantitative (TA) and qualitative (news) inputs.

---

### Future: MCP Server: Solana On-Chain Data

**Status:** Planned, not implemented in v1.

**What it would do:** Query the Solana blockchain for on-chain signals (DEX volume, whale movements, token flows).

**Why deferred:** Adds blockchain RPC dependency that could be unreliable during a live demo. Mentioned in the talk as an extension to prove modularity: "Adding a new data source is just adding a new MCP server Pod."

---

## Layer 3: Distribution

### EventBridge (Event Bus)

**What it is:** A serverless event routing service.

**Responsibility:** Receive signal events from the agent, evaluate rules against event content, route matching events to subscriber targets.

**Uses LLM?** No.

**Rules:**

| Rule Name | Condition | Target |
|-----------|-----------|--------|
| `telegram-btc-high-confidence` | `asset = "BTC" AND confidence > 0.8` | Telegram bot Lambda |
| `dashboard-all` | `(all signals)` | Dashboard WebSocket API |
| `email-high-confidence` | `confidence > 0.9` | Email notification Lambda |
| `solana-sol-buy` | `asset = "SOL" AND signal = "BUY"` | Solana executor (future) |

---

### Subscriber: Telegram Bot

**What it is:** A Lambda function triggered by EventBridge.

**Uses LLM?** No.

**Message format:**
```
🟢 GO Signal — BTC 15min (UP)
Confidence: 82% | EV: +12.5% | Kelly: 14%

📊 Indicators:
RSI: 34.2 (oversold)
MACD: Bullish crossover
Bollinger: Lower band

📰 Sentiment: Positive
"Institutional BTC accumulation reported"

💰 Suggested: $70 (half-Kelly on $1000 bankroll)

⏰ 2026-03-09 15:30 UTC
```

---

### Subscriber: Web Dashboard

**What it is:** A simple web interface showing all signals in real time.

**Priority:** Nice-to-have. The Telegram bot is the primary visual proof for the live demo.

---

## Component Summary: What Uses LLM and What Doesn't

| Component | Uses LLM? | Where it Runs | Cost Tier | Status |
|-----------|-----------|--------------|-----------|--------|
| Watchdog (El Vigía) | ❌ No | ARM node | Cheap | ✅ Phase 3 |
| Strategist (El Estratega) | ✅ Yes (main consumer) | ARM node (process) + GPU/Inferentia (inference) | Cheap process + Expensive LLM calls | ✅ Phase 1-2 |
| Broadcaster (BroadcasterNode) | ❌ No | ARM node | Free (pure math) | ✅ Phase 1 |
| Context Analyst | ✅ Yes (small model) | ARM node (process) + GPU/Inferentia (inference) | Cheap — lightweight summarization | ✅ Phase 4 |
| ChromaDB / Amazon OpenSearch Service (VectorStore) | ❌ No | In-process (local) / AWS managed service (EKS) | Free locally / pay-per-use | ✅ Phase 4 (local) / ⏳ EKS |
| MCP: Polymarket | ❌ No | ARM node | Cheap | ✅ Phase 2 |
| MCP: Technical Analysis | ❌ No | ARM node | Cheap | ✅ Phase 2 |
| MCP: Web Search | ❌ No | ARM node | Cheap | ✅ Phase 2 |
| vLLM (GPU) | ✅ Serves the LLM | GPU node | Expensive | ⏳ EKS |
| vLLM (Neuron) | ✅ Serves the LLM | Inferentia node | Medium | ⏳ EKS |
| LiteLLM Gateway | ❌ No | ARM node | Cheap | ⏳ EKS |
| LangFuse | ❌ No | ARM node | Cheap | ⏳ EKS |
| Prometheus + Grafana | ❌ No | ARM node | Cheap | ⏳ EKS |
| EventBridge | ❌ No | Serverless | Pay-per-event | ⏳ EKS |
| Telegram Bot Lambda | ❌ No | Serverless | Pay-per-invocation | ⏳ EKS |

**The takeaway:** Only 3 out of 15 components need expensive accelerated hardware. The rest run on ARM (~$0.04/hr) or serverless (pay-per-event). This is the cost optimization story of the talk.

---

## Communication Map

```
Tavily API (external) ──► ingest_context.py ──► Context Analyst ──┐
                          (--fetch-news CLI)     (Llama 3.1 8B)    │
                                                                    │ upsert
Coinbase WS (default) ───────────────┐                             ▼
  (or Binance WS fallback)           │                       ChromaDB (local)
Polymarket WS ───────────────────────┤                       Amazon OpenSearch Service
                                     ▼                             │
                              Watchdog (asyncio)                   │ query_vectordb() top-k
                                     │ graph.invoke_async(         │
                                     │ invocation_state)           ▼
                                     ▼
Polymarket API (external)     Strategist (Strands Agent)  ──→ LiteLLM ──→ vLLM-GPU
       │                        ↑        ↑        ↑                  └──→ vLLM-Neuron
       ▼                        │        │        │
MCP: Polymarket ────────────────┘        │        │
                                         │        │
Tavily API (external)                    │        │
       │                                 │        │
       ▼                                 │        │
MCP: Web Search ─────────────────────────┘        │
                                                   │
MCP: Tech Analysis ────────────────────────────────┘
                                     │
                              has_positive_ev()?
                              (reads structured_output)
                                     │ GO
                                     ▼
                              Broadcaster (FunctionNode)
                              EV/Kelly math → _emit()
                                     │
                              local: console log        ────► auto-ingest signal_log
                              EKS:   EventBridge                 to ChromaDB
                                          │
                              ┌───────────┼───────────┐
                              ▼           ▼           ▼
                         Telegram    Dashboard    (Solana)
```

All internal communication is HTTP/REST within the EKS cluster (or localhost in local dev).
External dependencies: Coinbase WS (public, default) or Binance WS (public, optional), Polymarket WS + API (public), Tavily API (key required).

**Hybrid memory (RAG):** Tavily news is ingested via CLI before running the loop. Each GO signal
is automatically ingested as `signal_log` during the loop. The Strategist queries ChromaDB at the
start of each cycle to retrieve relevant historical context before making its GO/NO_GO decision.

**VectorStore backends:** ChromaDB (local in-process, no infrastructure needed) → Amazon OpenSearch
Service (EKS, `VECTOR_BACKEND=opensearch`). AWS managed: no cluster to operate, just an endpoint.

**Embeddings on EKS:** The LiteLLM gateway (already in the architecture) exposes a `/embeddings`
endpoint. `OpenSearchVectorStore` calls `POST litellm-gateway:4000/embeddings` to convert text →
vector before upsert/query. LiteLLM routes to whatever embedding model is configured
(e.g., `nomic-embed-text` on vLLM, or `text-embedding-ada-002`). No extra infrastructure.

The swap local → EKS is a one-line env var change — no agent code changes.
