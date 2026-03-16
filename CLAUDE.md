# CLAUDE.md

> **Status: Phases 1–4 implemented locally.** EKS deployment is pending.

> **Local setup note:** The package must be installed in editable mode before running any script, otherwise `ModuleNotFoundError: No module named 'agents'` is raised.
> ```bash
> cd demo-polymarket
> uv pip install -e ".[dev]"   # or: pip install -e .
> ```

## Development Rules

### Strands Agents SDK — Always consult the docs first

**Before writing ANY code that uses Strands Agents SDK**, use the `strands-docs` skill (or invoke it manually with `/strands-docs`) to fetch and verify the current API from https://strandsagents.com/docs/. The live documentation is the source of truth — not the code examples in this file. If the docs differ from what this CLAUDE.md describes, follow the docs and flag the discrepancy.

## Project Context

This repository contains the demo for the talk **"Orchestrating Intelligence: Multi-Architecture LLM Serving on Amazon EKS"**.

The demo is a **real-time trading signal agent** for prediction markets (Polymarket). It monitors BTC via Coinbase 5-minute candles, predicts UP or DOWN over the current 15-minute Polymarket window, and generates GO/NO_GO signals with confidence scores, Expected Value (EV), and Kelly Criterion sizing, then distributes them to subscribers in real time.

The purpose of this demo is NOT the trading agent itself — it is the **vehicle** to demonstrate how Amazon EKS orchestrates LLM inference across multiple hardware architectures (NVIDIA GPUs, AWS Inferentia, AWS Graviton) transparently. The agent doesn't know or care what chip its "brain" runs on.

## Tech Stack

| Layer | Technology | Why |
|-------|-----------|-----|
| Agent Framework | **Strands Agents SDK** | AWS-native, built-in OpenTelemetry tracing, native `@tool` decorators, MCP client support. Used in the official AWS Guidance for Scalable Model Inference on EKS. |
| Model Serving | **vLLM** | High-performance inference engine. OpenAI-compatible API. Supports both CUDA (GPU) and Neuron SDK (Inferentia). |
| Model Gateway | **LiteLLM** (primary) or **Envoy AI Gateway** (alternative) | Unified `/v1/chat/completions` endpoint in front of all backends. Routing, failover, token tracking. |
| Strands ↔ Models | **LiteLLM provider** or **OpenAI provider** (pointing to LiteLLM URL) | Strands connects to models via the gateway, never directly to vLLM. This is what makes hardware abstraction possible. |
| MCP Servers | **Custom Python services** using MCP protocol (SSE) | Polymarket data, Technical Analysis, Web Search. Each runs as a separate Pod on ARM nodes. |
| Event Bus | **Amazon EventBridge** | Content-based filtering rules route signals to subscribers. |
| Observability | **LangFuse** (agent traces) + **Prometheus/Grafana** (infra metrics) | Two-layer observability: agent decisions and infrastructure efficiency. |

## Architecture Overview

The system has three layers:

### Layer 1: Platform (EKS Multi-Architecture)

An EKS cluster with multiple compute node pools managed by Karpenter:

- **ARM-based nodes (Graviton)** — Run all lightweight services: LiteLLM gateway, MCP servers, the Strands agent process, observability tools, EventBridge integration. Cost-optimized CPU nodes (~$0.04/hr vs ~$1/hr for GPU).
- **GPU nodes (g5/g6)** — Run vLLM with CUDA for LLM inference. High-performance but expensive.
- **ML accelerator nodes (inf2)** — Run vLLM with Neuron SDK for LLM inference. 40-70% cheaper than GPU. Requires model compilation with `optimum-neuron`.

Device plugins expose hardware accelerators to Kubernetes so pods can request them as resources. Karpenter observes pending pods and provisions the right instance type automatically.

### Layer 2: Intelligence (Agent System)

A Strands Graph-based architecture with specialized components. See `docs/agent-patterns.md` for full details and `docs/agent_flow.mermaid` for the visual diagram.

- **Watchdog** — asyncio watchdog (not a Strands agent). Monitors Coinbase (default) or Binance + Polymarket WebSockets 24/7 on ARM, triggers the Graph on candle close or volatility spike.
- **Strategist** — Graph entry_point node. Reasons with a large model (30B-70B) via LiteLLM gateway + RAG from vector database. Emits GO/NO_GO with probability estimate.
- **Conditional Edge** — Pure Python function that routes the Graph based on the Strategist's decision. No LLM.
- **Broadcaster** — FunctionNode. Calculates EV/Kelly, formats signal, sends to subscribers. 100% deterministic, no LLM.
- **Context Analyst** — Background agent that feeds the vector database for RAG.

- **MCP Servers (separate Pods on ARM):**
  - **Polymarket API** — Real-time market data: active markets, odds, volume, price history.
  - **Technical Analysis** — Quantitative indicators: RSI, MACD, Bollinger Bands, VWAP. The LLM is bad at math — we delegate calculations to specialized tools.
  - **Web Search** — Recent news and sentiment via Tavily API.

**Important distinction:** MCP servers handle external data retrieval (network I/O, reusable across agents). Deterministic logic (EV/Kelly, formatting, notification) lives in the Broadcaster FunctionNode. See `docs/architecture.md` Decision 3 for the full rationale.

### Layer 3: Distribution (EventBridge)

Once the agent generates a signal, it publishes to EventBridge. Rules inspect event content and route to specific subscribers:

- Telegram bot (filtered: e.g., only BTC signals with confidence > 0.8)
- Web dashboard (all signals)
- Email notifications (only high confidence)
- Solana executor (future: SOL BUY signals only)

Subscribers only receive what they care about — filtering is centralized, not per-consumer.

## Signal Output Format

```json
{
  "asset": "BTC",
  "timeframe": "5min",
  "signal": "BUY",
  "confidence": 0.82,
  "ev_pct": 12.5,
  "kelly_fraction": 0.14,
  "suggested_size_usd": 70.0,
  "indicators": {
    "rsi": 34.2,
    "macd_signal": "bullish_crossover",
    "bollinger_position": "lower_band"
  },
  "market": {
    "polymarket_odds": 1.65,
    "polymarket_volume": 45200
  },
  "sentiment": "positive",
  "reasoning": "RSI indicates oversold conditions, MACD showing bullish crossover, recent news about institutional BTC accumulation supports upward momentum. EV is positive at 12.5% with Kelly suggesting 14% of bankroll.",
  "timestamp": "2026-03-09T15:30:00Z"
}
```

## Model Configuration

See `docs/models.md` for full details. Summary:

| Component | Model | Hardware | Connection |
|-----------|-------|----------|------------|
| Strategist (reasoning) | Qwen3-30B or Llama 3.1 70B (quantized) | GPU via vLLM | Via LiteLLM gateway |
| Context Analyst (background) | Llama 3.1 8B-Instruct | GPU or Inferentia via vLLM | Via LiteLLM gateway |
| Broadcaster | None (deterministic) | ARM node | N/A |
| Watchdog | None (asyncio) | ARM node | N/A |

LiteLLM handles routing and failover. The agents connect to the gateway, never directly to vLLM.

## Strands Graph Setup Pattern

See `docs/agent-patterns.md` for the complete code. Summary of the key connection:

```python
from strands import Agent, tool, ToolContext
from strands.models.litellm import LiteLLMModel
from strands.multiagent import GraphBuilder

# Connect to models via LiteLLM gateway (hardware-agnostic)
reasoning_model = LiteLLMModel(
    model_id="llama-3.1-8b",           # LiteLLM routes this to the right backend
    base_url="http://litellm-gateway:4000",
)

# Strategist — reasoning agent (entry_point)
strategist = Agent(
    name="strategist",
    model=reasoning_model,
    system_prompt="You are a market analyst for BTC prediction markets...",
    tools=[query_vectordb, get_market_snapshot],
)

# Graph: Strategist → (condition) → Broadcaster
builder = GraphBuilder()
builder.add_node(strategist, "strategist")
builder.add_node(BroadcasterNode(), "broadcaster")  # FunctionNode, no LLM
builder.add_edge("strategist", "broadcaster", condition=has_positive_ev)
builder.set_entry_point("strategist")
graph = builder.build()

# Watchdog triggers the Graph
result = graph.invoke("Analyze BTC 15min candle", invocation_state={...})
```

The agent connects to models via LiteLLM, never directly to vLLM. This is what makes hardware abstraction possible — the same code works whether the model runs on GPU or Inferentia.

## Key Principles

1. **Hardware abstraction** — The application layer never references specific chips. It requests "an accelerator" and the platform decides. The Strands agent connects to LiteLLM, not to a specific vLLM instance.
2. **Cost optimization** — Only inference workloads run on expensive accelerated hardware. Everything else (agent, MCP servers, gateway, observability) runs on the cheapest ARM-based compute.
3. **Modularity** — Each MCP service is independent and replaceable. Adding a new data source means adding a new MCP server Pod, not modifying the agent.
4. **Math belongs in tools** — The LLM interprets data and reasons about signals. Calculations (RSI, MACD, EV, Kelly) are delegated to deterministic tools that are correct every time.
5. **Observability** — Two layers: agent-level tracing via LangFuse (what did the agent do, how many tokens, what reasoning chain) and infrastructure-level monitoring via Prometheus/Grafana (GPU utilization, node scaling, cost per pool).

## Repository Structure

```
├── CLAUDE.md                  # This file — AI assistant context
├── README.md                  # Project overview and quickstart
├── docs/                      # Architecture docs, talk materials, diagrams
├── infrastructure/            # Terraform IaC (networking, IAM, EKS, cluster services)
├── kubernetes/                # K8s manifests (Inferentia, GPU, model storage examples)
├── specs/                     # Planning docs
└── demo-polymarket/           # Application code (agent + services + demo scripts)
    ├── pyproject.toml         # Python package config
    ├── docker-compose.yml     # Local MCP servers + ChromaDB
    ├── agents/                # Agent application code
    │   ├── strategist/        # Reasoning agent + prompts + RAG tool
    │   ├── broadcaster/       # Deterministic EV/Kelly FunctionNode
    │   ├── watchdog/          # asyncio WebSocket monitor
    │   └── context_analyst/   # Background RAG agent + ingest CLI
    ├── services/              # MCP servers
    │   ├── polymarket/        # Polymarket API MCP server
    │   ├── technical_analysis/# TA indicators MCP server (RSI, MACD, etc.)
    │   ├── web_search/        # Tavily web search MCP server
    │   └── vectorstore/       # VectorStore abstraction (Chroma/OpenSearch)
    ├── tests/                 # pytest test suite
    └── demo/                  # Demo scripts and utilities
```

## Agent Architecture

The demo uses the Strands Graph pattern with specialized components. See `docs/agent-patterns.md` for full details and `docs/agent_flow.mermaid` for the visual diagram.

- **Watchdog** — asyncio watchdog that triggers the Graph (not a Strands agent, no LLM). Monitors Coinbase + Polymarket WebSockets 24/7 on ARM.
- **Strategist** — Graph entry_point node with reasoning model (30B-70B) and RAG. Decides GO/NO_GO.
- **Conditional Edge** — Python function routing GO/NO_GO based on GraphState. No LLM.
- **Broadcaster** — FunctionNode (custom MultiAgentBase) for deterministic EV/Kelly calculation and notification dispatch. No LLM.
- **Context Analyst** — Background agent feeding the vector database for RAG.

Key patterns: `invocation_state` (shared context invisible to LLM), structured output (Pydantic models for reliable conditional edge parsing).

The talk focuses on the infrastructure story (EKS multi-arch, Karpenter, device plugins, vLLM, LiteLLM). The agent architecture demonstrates how these components work together but is not the main topic.

## What This Is NOT

- NOT a production trading system. Do not use signals for real financial decisions.
- NOT a model training pipeline. We use pre-trained models and serve them.
- NOT a Polymarket trading bot. We generate signals, we don't execute trades.

## Talk Reference

Title: "Orchestrating Intelligence: Multi-Architecture LLM Serving on Amazon EKS"

Key message: "Deploying GenAI shouldn't be a hardware headache. Whether you run on NVIDIA GPUs or AWS Inferentia, Amazon EKS is the ultimate orchestrator."

The demo proves this by showing the same agent working identically regardless of which accelerator serves the underlying model.
