# Agent Patterns with Strands Agents SDK

> **Status: Phases 1–4 implemented locally.** EKS deployment is pending.

## Overview

This document describes the multi-agent patterns available in Strands Agents SDK and how they apply to this project. It serves as both a reference for the talk and the blueprint for the demo's agent architecture.

The demo uses the **Graph pattern** with specialized components: El Vigía (infrastructure watchdog), El Estratega (reasoning agent), Arista Condicional (deterministic routing), and El Mensajero (deterministic broadcaster). The talk focuses on the infrastructure layer (EKS, Karpenter, vLLM, LiteLLM), but this agent architecture is what runs on top of it.

---

## Strands Agents SDK — Key Concepts

### What Strands Is (and Isn't)

Strands is an agent **orchestration** SDK. It does NOT run inference. It sends requests to an external model endpoint (vLLM, Ollama, Bedrock, etc.) and orchestrates the reasoning loop: think → call tool → observe → think again → respond.

When you call `agent("analyze BTC")`, Strands enters a ReAct loop internally. The LLM decides which tools to call and in what order. Once it has enough information, it produces a final response and stops. The agent does not stay running — it completes the task and returns.

This means Strands is designed to be **invoked by something external**, not to run as a daemon listening for events. For Always-On systems, the listening layer is pure infrastructure (asyncio, cron, queue consumer) that triggers Strands when needed.

### The Agent Loop

```
Input → LLM thinks → decides to call tool → tool executes → result back to LLM
                    → decides to call another tool → ...
                    → decides it has enough info → final response → done
```

This is the default single-agent pattern. The LLM autonomously decides the tool sequence. Good for demos and simple workflows.

### Multi-Agent Patterns

Strands 1.0 provides four orchestration primitives for multi-agent systems:

| Pattern | How Execution Path Is Determined | Best For |
|---------|--------------------------------|----------|
| **Graph** | Developer defines nodes + edges + conditions. Deterministic routing. | Structured workflows with conditional branches. |
| **Swarm** | Agents hand off to each other dynamically. LLM decides next agent. | Exploration, brainstorming, collaborative tasks. |
| **Agents as Tools** | One agent calls others as if they were tools. Hierarchical. | Delegation to domain specialists. |
| **Workflow** | Fixed dependency DAG with parallel execution. | Repeatable pipelines with no branching. |

For this project, **Graph** is the right pattern because we need conditional routing (GO/NO_GO) and deterministic execution when the stakes matter (signal emission).

---

## Production Architecture: The Graph Pattern

### Components

The system has 4 components. Only 2 use LLMs.

| Component | What It Is | Uses LLM? | Strands Pattern |
|-----------|-----------|-----------|----------------|
| **El Vigía** (Watchdog) | asyncio Python script. Listens to Coinbase (default) or Binance + Polymarket WebSockets. Triggers the Graph on `candle_close` or `volatility_spike`. | ❌ No | Not Strands — pure infrastructure |
| **El Estratega** (Strategist) | Strands Agent (`name="strategist"`). Reasons about market data via MCP tools. Emits `StrategistDecision` (GO/NO_GO). Local: Claude via Anthropic API. EKS: LiteLLM → vLLM (GPU/Inferentia). | ✅ Yes | Graph entry_point node |
| **Arista Condicional** | `has_positive_ev(GraphState)` — reads `structured_output` from the Strategist result. | ❌ No | Graph conditional edge |
| **Broadcaster** (`BroadcasterNode`) | Deterministic node. Calculates EV/Kelly from `StrategistDecision` + `invocation_state`. Emits signal to console (local) / EventBridge (EKS). | ❌ No | FunctionNode (custom MultiAgentBase) |

### Why This Design

The key insight is separating **who listens** from **who thinks** from **who acts**:

- **El Vigía listens.** Runs 24/7 on a cheap CPU Pod. Monitors WebSockets. No LLM, no GPU. Costs ~$0.04/hr.
- **El Estratega thinks.** Invoked only when needed (~96 times/day for 15min candles). Uses a large reasoning model on GPU. Expensive but brief.
- **El Mensajero acts.** Calculates and sends. Zero LLM calls. Deterministic. Takes ~100ms.

If you ran a single agent 24/7 waiting for events, you'd pay GPU prices for a process that's idle 99% of the time. This design pays for GPU only during the ~5-10 seconds of actual reasoning per candle.

---

## El Vigía (Watchdog) — Infrastructure Layer

The Vigía is NOT a Strands agent. It's a pure asyncio Python script running as a Kubernetes Deployment on an ARM node.

### What It Does

1. Connects to WebSockets (Coinbase for BTC 5-minute candles by default, Binance as optional fallback; Polymarket for odds)
2. Accumulates OHLCV data for the current candle
3. When a trigger condition is met, invokes the Strands Graph
4. Resets and waits for the next candle

### Trigger Conditions

The Vigía fires the Graph when ANY of these conditions is true:

```python
# Candle close: detected when a newer candle start timestamp is observed
# (Coinbase does not send an explicit close flag; Binance uses kline["x"])
if new_candle_started:
    trigger = "candle_close"

# Volatility spike: intra-candle move exceeds threshold (once per candle)
elif abs(close - open) / open >= VOLATILITY_SPIKE_THRESHOLD:
    trigger = "volatility_spike"
```

`candle_close` waits for the complete, final OHLCV before triggering — this ensures all technical indicators are calculated on confirmed data. `volatility_spike` allows early reaction to large intra-candle moves.

### How It Invokes Strands

```python
result = graph.invoke(
    "Analyze BTC 15min candle for trading signal",
    invocation_state={
        "ohlcv": candle_data,        # {open, high, low, close, volume}
        "polymarket_odds": odds,      # e.g. 1.65
        "timestamp": candle_close_ts, # when the candle closes
        "volatility": rolling_vol,    # rolling volatility metric
        "trigger_reason": trigger,    # "candle_close" or "volatility_spike"
        "bankroll": 1000,             # for Kelly sizing
    }
)
```

### Key Detail: invocation_state

`invocation_state` is a dict shared across ALL nodes in the Graph. It is NOT injected into the LLM prompt — it's invisible to the model. Tools access it via `tool_context.invocation_state`. This is where raw market data lives: the LLM doesn't need to see OHLCV arrays, but tools do.

What the LLM DOES see is the task string ("Analyze BTC 15min candle...") and the results of tool calls it makes.

---

## El Estratega (Strategist) — Graph Entry Point

### What It Does

1. Calls RAG tool to get historical context from the vector database
2. Calls a tool to read market data from `invocation_state`
3. Reasons about all available information
4. Emits a structured decision: GO or NO_GO with a probability estimate

### Strands Agent Definition

```python
from strands import Agent, tool
from strands.models.litellm import LiteLLMModel
from strands.tools.mcp import MCPClient
from strands.types.tools import ToolContext
from mcp.client.sse import sse_client

# LOCAL:  Anthropic API via LiteLLM
# EKS:    LiteLLM gateway → vLLM (GPU or Inferentia) — only config changes
model = LiteLLMModel(
    client_args={"api_key": ANTHROPIC_API_KEY},
    model_id="anthropic/claude-haiku-4-5-20251001",
    params={"max_tokens": 1024, "temperature": 0.3},
)

@tool(context=True)
def get_market_snapshot(tool_context: ToolContext) -> str:
    """Get current candle data and Polymarket odds from the Vigía's data."""
    state = tool_context.invocation_state
    ohlcv = state.get("ohlcv", {})
    return (
        f"Open: ${ohlcv.get('open'):,.2f}  High: ${ohlcv.get('high'):,.2f}  "
        f"Low: ${ohlcv.get('low'):,.2f}  Close: ${ohlcv.get('close'):,.2f}\n"
        f"Polymarket odds: {state.get('polymarket_odds')}x  "
        f"Trigger: {state.get('trigger_reason')}"
    )

# MCP servers (USE_MCP=true, requires docker compose up)
ta_mcp        = MCPClient(lambda: sse_client(url="http://localhost:8002/sse"))
polymarket_mcp = MCPClient(lambda: sse_client(url="http://localhost:8001/sse"))
search_mcp    = MCPClient(lambda: sse_client(url="http://localhost:8003/sse"))

estratega = Agent(
    name="strategist",
    model=model,
    system_prompt="...",   # see agents/strategist/prompts.py
    tools=[get_market_snapshot, ta_mcp, polymarket_mcp, search_mcp],
    structured_output_model=StrategistDecision,
)
```

Note: Set `USE_RAG=true` to enable RAG — the Strategist will call `query_vectordb()` before deciding. Requires `ingest_context.py` to have been run first. When `USE_MCP=false`, falls back to `get_historical_context` stub.

### Structured Output

`structured_output_model=StrategistDecision` tells Strands to parse the final agent response into a typed Pydantic model — no regex needed:

```python
from pydantic import BaseModel
from typing import Literal

class StrategistDecision(BaseModel):
    decision:    Literal["GO", "NO_GO"]
    probability: float   # e.g. 0.60
    direction:   Literal["UP", "DOWN"]
    confidence:  float   # 0.0 to 1.0
    reasoning:   str
```

The conditional edge reads `agent_result.structured_output` directly — type-safe and takes microseconds.

### Model Choice

**Local (dev):** Claude Haiku via Anthropic API — cheap and fast for testing.

**EKS (production):** Large reasoning model (Qwen3-30B or Llama 3.1 70B quantized) via LiteLLM gateway → vLLM on GPU or Inferentia. Only `config.py` changes — agent code is identical. The Estratega needs to synthesize multiple data sources (candle, odds, news) and make nuanced probability estimates; a small model (8B) doesn't reason well enough for this.

---

## Arista Condicional — Graph Routing

A pure Python function that reads the Estratega's structured output and decides if the Graph continues to the Broadcaster or stops.

```python
from strands.multiagent.graph import GraphState
from agents.models import StrategistDecision

def has_positive_ev(state: GraphState) -> bool:
    """Only proceed to the Broadcaster if the Estratega said GO."""
    node_result = state.results.get("strategist")
    if not node_result:
        return False
    # Primary: typed structured output (StrategistDecision)
    decision = getattr(node_result.result, "structured_output", None)
    if decision is not None:
        return decision.decision == "GO"
    # Fallback: text check
    return '"decision": "go"' in str(node_result.result).lower()
```

If this returns `False`, the Graph completes without executing the Broadcaster. No signal is emitted. The Watchdog logs the result and waits for the next candle.

This is NOT an LLM call. It's a string check that takes microseconds.

---

## Broadcaster (BroadcasterNode) — FunctionNode

### Why Not a Regular Agent

The Broadcaster's job is 100% deterministic:
1. Deserialize the Strategist's `StrategistDecision` (structured output)
2. Read odds and bankroll from `invocation_state`
3. Calculate EV and Kelly (3 lines of math)
4. Format the signal
5. Emit — locally: print to console; on EKS: publish to EventBridge

There is zero reasoning involved. Using an LLM for this would be slower, more expensive, and non-deterministic. A `FunctionNode` extending `MultiAgentBase` is the right choice.

### Implementation

```python
from strands.multiagent.base import MultiAgentBase, MultiAgentResult, Status
from agents.models import StrategistDecision, Signal

class BroadcasterNode(MultiAgentBase):
    """Deterministic node: calculate EV/Kelly, format signal, emit."""

    async def invoke_async(self, task, invocation_state=None, **kwargs):
        invocation_state = invocation_state or {}

        # 1. Deserialize Strategist's structured decision
        decision = StrategistDecision.model_validate_json(str(task))

        # 2. Read context from invocation_state
        odds     = invocation_state.get("polymarket_odds", 1.65)
        bankroll = invocation_state.get("bankroll", 1000)

        # 3. Calculate EV and Kelly
        b      = odds - 1.0
        ev     = decision.probability * b - (1 - decision.probability)
        kelly  = ev / b if ev > 0 and b > 0 else 0.0
        size   = round(bankroll * kelly * 0.5, 2)  # half-Kelly

        # 4. Build signal
        signal = Signal(
            asset=invocation_state.get("asset", "BTC"),
            timeframe=invocation_state.get("timeframe", "15min"),
            signal="BUY" if decision.direction == "UP" else "SELL",
            ev_pct=round(ev * 100, 2),
            kelly_fraction=round(kelly, 4),
            suggested_size_usd=size,
            polymarket_odds=odds,
            probability_estimate=decision.probability,
            confidence=decision.confidence,
            reasoning=decision.reasoning,
            timestamp=invocation_state.get("timestamp"),
        )

        # 5. Emit signal
        self._emit(signal)  # console locally / EventBridge on EKS

        return MultiAgentResult(status=Status.COMPLETED)
```

### Latency

The Broadcaster takes ~10-50ms (pure Python math + I/O). Compare this to an LLM agent which would take 3-10 seconds for the same task.

---

## Assembling the Graph

```python
from strands.multiagent import GraphBuilder

builder = GraphBuilder()

# Add nodes
builder.add_node(estratega, "strategist")
builder.add_node(BroadcasterNode(), "broadcaster")

# Conditional edge: only go to broadcaster if +EV
builder.add_edge("strategist", "broadcaster", condition=has_positive_ev)

# Entry point
builder.set_entry_point("estratega")

# Production safety: timeout and execution limits
builder.set_execution_timeout(90)       # Max 90 seconds for the whole graph
builder.set_max_node_executions(1)      # No accidental loops

# Build
graph = builder.build()
```

### Execution Flow

```
Watchdog calls graph.invoke_async("Analyze BTC...", invocation_state={...})
    │
    ▼
┌──────────────────────┐
│   Strategist          │  ← LLM reasons (5-10 sec locally, faster on EKS)
│   (entry_point)       │  ← Calls get_market_snapshot(), MCP tools (TA/Polymarket/Search)
│   → StrategistDecision│
└──────────┬───────────┘
           │
      has_positive_ev(state)?
      reads structured_output
           │
      ┌────┴────┐
      │ False   │ True
      │         │
      ▼         ▼
    DONE    ┌──────────────┐
    (no     │  Broadcaster  │  ← No LLM, ~10-50ms
    signal) │  EV + Kelly   │
            │  _emit()      │  ← console (local) / EventBridge (EKS)
            └──────────────┘
```

### Graph Results

```python
result = graph.invoke("Analyze BTC...", invocation_state={...})

print(result.status)           # COMPLETED
print(result.execution_time)   # 6200 (ms)
print(result.total_nodes)      # 2
print(result.completed_nodes)  # 1 or 2 (depending on GO/NO_GO)
print(result.accumulated_usage)  # token counts
```

---

## Data Flow Summary

```
                    invocation_state (shared, not in LLM prompt)
                    ┌──────────────────────────────────────────┐
                    │ ohlcv, odds, bankroll, timestamp, vol    │
                    └────┬─────────────────────────┬───────────┘
                         │                         │
                    read by tools             read by FunctionNode
                         │                         │
                         ▼                         ▼
WebSockets ──► Vigía ──► Graph ──► Estratega ──► Mensajero
                              │         │              │
                              │    AgentResult         │
                              │    (GO, prob=0.60,     │
                              │     direction=UP)      │
                              │         │              │
                              │    travels via edge    │
                              │         └──────────────┘
                              │
                         invocation_state does NOT travel
                         between nodes — it's shared by
                         reference to ALL nodes at invocation
```

### Important Distinction

- **`invocation_state`** = global context shared with all nodes. Set once by the Vigía. Contains raw data (OHLCV, odds, bankroll). NOT visible to the LLM.
- **`AgentResult`** = output of each node. Travels along edges. The Estratega's result (decision + probability) becomes the Mensajero's input.

---

## Background Component: Analista de Contexto (Memory Builder)

Not part of the Graph. Feeds the vector database that the Estratega queries via `query_vectordb()`.

### Hybrid Memory Strategy

Two paths to build the vector DB, used together:

| Path | When | Source |
|------|------|--------|
| **CLI ingest** | Before running the agent | `ingest_context.py --fetch-news` → Tavily API → real BTC news |
| **Auto-ingest** | After every GO signal | Watchdog calls `ingest_context()` with signal context → `signal_log` entry |

The CLI builds historical context before the first cycle. Auto-ingest builds memory over time: past GO signals, price levels, setups that worked. This is how the system learns what setups actually produce positive EV.

**Embeddings per environment:**

| Environment | Who generates embeddings | How |
|-------------|------------------------|-----|
| Local | ChromaDB built-in | ONNX model `all-MiniLM-L6-v2`, automatic |
| EKS | LiteLLM gateway `/embeddings` | `POST litellm-gateway:4000/embeddings` → any configured embedding model (`nomic-embed-text`, `text-embedding-ada-002`, etc.) |

The same LiteLLM gateway already used for chat completions also handles embeddings — no extra pods or services needed on EKS.

### Implementation

```python
from strands import Agent
from strands.models.litellm import LiteLLMModel
from services.vectorstore.factory import get_vector_store

# LOCAL: Claude Haiku via Anthropic  |  EKS: Llama 3.1 8B via LiteLLM → vLLM
model = LiteLLMModel(
    client_args={"api_key": ANTHROPIC_API_KEY},
    model_id="anthropic/claude-haiku-4-5-20251001",
)

analista = Agent(
    name="context_analyst",
    model=model,
    system_prompt="Summarize the key trading insights from this text...",
)

async def ingest_context(raw_text: str, asset: str = "BTC", source: str = "manual") -> str:
    """Summarize raw text and upsert into ChromaDB."""
    result = await analista.invoke_async(f"Analyze and summarize:\n\n{raw_text}")
    summary = str(result)
    vs = get_vector_store()
    doc_id = f"{asset}_{source}_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}"
    vs.upsert(doc_id=doc_id, text=summary, metadata={"asset": asset, "source": source})
    return summary
```

Uses a **small, fast model** (8B) because it's doing lightweight summarization, not deep reasoning.

### CLI Usage

```bash
# Fetch REAL news from Tavily and ingest
./.venv/bin/python agents/context_analyst/ingest_context.py --fetch-news

# Ingest sample contexts (no API key needed)
./.venv/bin/python agents/context_analyst/ingest_context.py --sample

# Ingest custom text
./.venv/bin/python agents/context_analyst/ingest_context.py --asset BTC --source news \
  --text "BTC ETF net inflows +$420M in 24h..."
```

### Auto-Ingest Loop

When `USE_RAG=true` and the Strategist says GO, the Watchdog spawns a background task:

```python
# In run_watchdog_graph_loop — fires after each GO decision
if decision.decision == "GO":
    asyncio.create_task(_auto_ingest_signal(decision=decision, state=state))
```

This runs as fire-and-forget (never blocks the main loop). Each GO signal becomes a `signal_log` entry in ChromaDB — the next time a similar setup appears, the Strategist retrieves it via RAG.

---

## Model Recommendations per Component

| Component | Model Type | Recommended | GPU Node | Why |
|-----------|-----------|------------|----------|-----|
| Estratega | Reasoning (large) | Qwen3-30B-Q4_K_M or Llama 3.1 70B-Q4_K_M | g5.2xlarge (24GB) | Needs to synthesize multiple sources and make nuanced probability estimates |
| Analista de Contexto | Fast (small) | Llama 3.1 8B or Qwen3-4B | g5.xlarge (24GB, shared) | Lightweight summarization and extraction |
| Mensajero | None | — | CPU only | FunctionNode, no LLM |
| Vigía | None | — | CPU only | Pure asyncio, no LLM |

### Model Serving for Local Models

Both Ollama and llama.cpp are supported by Strands:

```python
# Ollama
from strands.models.ollama import OllamaModel
model = OllamaModel(host="http://ollama-service:11434", model_id="qwen3:30b")

# llama.cpp
from strands.models.llamacpp import LlamaCppModel
model = LlamaCppModel(base_url="http://llamacpp-service:8080", model_id="default")
```

Both serve an OpenAI-compatible API and support tool calling, which Strands requires.

### Important: Not All Models Support Tool Calling

Strands needs models with native function-calling support. Models that only do text completion will not work. Tested models with good tool-calling support:

- Llama 3.1 (8B, 70B) — Instruct variants
- Qwen3 (4B, 30B)
- Mistral 7B v0.3

---

## Relationship to the Talk

This is the agent architecture that runs on the EKS multi-arch infrastructure. The talk focuses on the infrastructure story — Karpenter, device plugins, vLLM, LiteLLM — and this agent is the vehicle that makes the demo tangible (signal arrives on Telegram).

See `docs/agent_flow.mermaid` for the visual flow diagram.

| Component | Runs On | Uses LLM? | Status |
|---|---|---|---|
| El Vigía (Watchdog) | ARM node (Graviton) | No | ✅ Implemented (Phase 3) |
| El Estratega (Strategist) | Calls LLM via LiteLLM → vLLM (GPU or Inferentia) | Yes | ✅ Implemented (Phase 1-2) |
| Arista Condicional (`has_positive_ev`) | Inside Graph (pure Python) | No | ✅ Implemented (Phase 1) |
| Broadcaster (`BroadcasterNode`) | ARM node (Graviton) | No | ✅ Implemented (Phase 1) |
| Analista de Contexto | Calls LLM via LiteLLM → vLLM | Yes (small model) | ✅ Phase 4 |
