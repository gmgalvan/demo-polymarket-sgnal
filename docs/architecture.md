# Architecture Decisions

> **Status: Phases 1–4 implemented locally.** EKS deployment is pending.

## Overview

This document captures the key architectural decisions for the trading signal agent demo, the reasoning behind each choice, and alternatives considered.

---

## Decision 1: Multi-Architecture Compute Strategy

### The Problem

LLM inference requires specialized hardware (GPUs or ML accelerators), but 80% of the workloads in our system are lightweight services that only need CPU — API gateways, MCP servers, agent logic, observability tools. Running everything on GPU nodes wastes money.

### The Decision

Three compute tiers managed by Karpenter:

| Tier | What Runs Here | Why |
|------|---------------|-----|
| ARM-based cost-optimized nodes (Graviton) | Strands agent, MCP servers, LiteLLM gateway, LangFuse, Prometheus/Grafana, EventBridge integration | Best price-performance for CPU workloads. 20-40% cheaper than x86 equivalents. |
| GPU nodes (g5/g6) | vLLM with CUDA (Llama 3.1 8B-Instruct) | Required for CUDA-based model serving. Industry standard with broadest model compatibility. |
| ML accelerator nodes (inf2) | vLLM with Neuron SDK (Llama 3.1 8B-Instruct, compiled) | AWS custom silicon. 40-70% cheaper than GPU for inference. Requires model compilation with `optimum-neuron`. |

### Why Not Just GPUs for Everything?

A GPU node costs ~$1/hr. An ARM node costs ~$0.04/hr. Running a proxy that just forwards HTTP requests on a GPU is a 25x cost overhead for zero benefit.

### Why Not Just ML Accelerators?

Not all models compile cleanly for Neuron. GPU remains the universal fallback. Having both gives flexibility: use accelerators when possible, fall back to GPU when needed.

---

## Decision 2: Agent Framework — Strands Agents SDK

### The Decision

Using **Strands Agents SDK** for agent orchestration.

### Why Strands

- **AWS-native** — Built-in integration with Bedrock, but also supports any OpenAI-compatible endpoint (which is what vLLM and LiteLLM expose).
- **OpenTelemetry tracing** — Automatic distributed tracing of the full agent loop: tool calls, token usage, reasoning steps. Feeds directly into LangFuse.
- **Native `@tool` decorator** — Define tools as Python functions. Strands handles schema generation, parameter validation, and injection into the LLM's tool-calling protocol.
- **MCP client support** — `MCPClient` connects to any MCP server and exposes its tools to the agent automatically.
- **Official AWS Guidance** — The AWS Guidance for Scalable Model Inference and Agentic AI on EKS uses Strands. Aligning with it means the demo is directly referenceable from AWS documentation.

### How Strands Connects to Models

Strands does NOT run inference itself. It sends requests to an external model endpoint. The connection chain:

```
Strands Agent  →  LiteLLM Gateway  →  vLLM (GPU)
                                   →  vLLM (Neuron)
```

In code, the agent connects via the LiteLLM or OpenAI provider:

```python
from strands.models.litellm import LiteLLMModel

model = LiteLLMModel(
    model_id="llama-3.1-8b",
    base_url="http://litellm-gateway:4000",
)
agent = Agent(model=model, tools=[...])
```

The agent has no idea which backend serves the request. This is the hardware abstraction in action.

### Alternatives Considered

- **CrewAI** — More visual, good for demos, but less integrated with AWS ecosystem. No native MCP support.
- **LangGraph** — Powerful graph-based workflows, but steeper learning curve for the audience. Strands Graph provides equivalent orchestration with simpler API and native AWS integration.
- **Custom** — Maximum flexibility but reinvents tracing, tool calling, MCP integration.

---

## Decision 3: MCP Servers vs Native Tools

### The Hybrid Approach

Not everything should be an MCP server, and not everything should be a native tool. The decision criteria:

**Use MCP Servers when:**
- The service is reusable across multiple agents or applications
- The service has its own lifecycle (can be updated independently)
- The service encapsulates an external API that might change
- The service benefits from being a separate scalable unit

**Use native `@tool` when:**
- The logic is specific to this agent only
- The function is lightweight (math, formatting, simple decisions)
- The function needs direct access to agent state or context
- Adding a network hop would add unnecessary latency

### Applied to Our System

**MCP Servers (separate Pods on ARM nodes):**

| MCP Server | Why MCP | External Dependency |
|-----------|---------|-------------------|
| Polymarket API | Wraps external API that changes independently. Reusable if other agents need market data. | Polymarket REST API |
| Technical Analysis | CPU-intensive numpy/pandas calculations. Reusable math library. | None |
| Web Search | Pre-built integration with search provider. Standard pattern. | Tavily API |

**Deterministic logic inside BroadcasterNode (not `@tool` decorators):**

| Logic | Why Inside Broadcaster | LLM Needed? |
|-------|----------------------|-------------|
| `calculate_ev_kelly(prob, odds)` | Depends on the Strategist's probability estimate — can't run until the LLM has reasoned. Pure Python math, agent-specific. | No |
| Signal formatting | Builds `Signal` Pydantic model from Strategist + `invocation_state`. Specific to this agent's output schema. | No |
| `_emit(signal)` | Prints to console locally. Publishes to EventBridge on EKS. Simple I/O, not reusable across agents. | No |

These live in `BroadcasterNode.invoke_async()` rather than as standalone `@tool` functions because they only run after the Strategist has decided GO — they are part of the deterministic execution path, not tools the LLM calls.

### Why EV/Kelly Is a Native Tool, Not in the TA MCP Server

The Technical Analysis MCP server calculates indicators from **market data** (RSI from prices, MACD from moving averages). These are purely data-derived.

EV and Kelly are different — they depend on the **agent's probability estimate**, which is the LLM's output after reasoning. The flow is:

```
MCP: Polymarket  → odds = 1.65
MCP: TA          → RSI = 34.2, MACD = bullish
MCP: Web Search  → sentiment = positive
         ↓
LLM reasons → "I estimate 60% probability of UP"
         ↓
Native tool: calculate_signal_metrics(prob=0.60, odds=1.65, bankroll=1000)
         → ev = +12.5%, kelly = 0.14, size = $70
```

The tool needs the LLM's opinion as input — it can't run before the LLM thinks. That makes it agent-specific, not a reusable service.

---

## Decision 4: Model Gateway — LiteLLM

### The Problem

We have two backends serving LLM inference (GPU and Inferentia). The Strands agent shouldn't need to know which one to call, handle failover, or manage routing.

### The Decision

**LiteLLM** as a unified API gateway in front of all vLLM backends:

- Single endpoint: `http://litellm-gateway:4000/v1/chat/completions`
- Routes to the appropriate vLLM backend based on model name or load
- Failover: if the GPU backend is down, redirect to Neuron (or vice versa)
- Rate limiting and access control
- Token and cost tracking per request
- Web UI for model management and monitoring

### Alternatives Considered

**Envoy AI Gateway:**
- Native Kubernetes Gateway API integration
- Higher performance (C++ proxy vs Python)
- Configured with CRDs (`kubectl apply`)
- No web UI — managed entirely via YAML
- Better for teams that want infrastructure-layer control

For this demo, LiteLLM is the primary choice because the web UI is visually useful during the live demo. The talk should mention Envoy AI Gateway as an equally valid option for production environments where infrastructure teams prefer CRD-based configuration.

---

## Decision 5: Model Selection — Llama 3.1 8B-Instruct

### The Decision

Llama 3.1 8B-Instruct as the reasoning model on both backends.

### Why This Model

- **Tool calling support** — Llama 3.1 Instruct has native function-calling capability, which Strands requires for the agent loop to work.
- **8B parameter size** — Fits on a single g5.xlarge (24GB A10G) without quantization. Also compiles for inf2.xlarge (2 Neuron cores). Keeps demo infrastructure minimal.
- **Same model, both backends** — Proves the talk's thesis: same model, different hardware, identical results. Using different models per backend would muddy the message.
- **Open weights** — No API keys or licensing complexity for the demo.

See `docs/models.md` for full details on quantization, compilation, and VRAM requirements.

---

## Decision 6: Signal Distribution — EventBridge

### The Decision

Amazon EventBridge with content-based filtering rules.

### How It Works

1. Broadcaster calls `_emit(signal)` inside `BroadcasterNode.invoke_async()`
2. **Locally:** prints formatted signal to console. **EKS:** sends structured event to EventBridge via boto3
3. Rules evaluate event content and route to matching targets:
   - `asset = "BTC" AND confidence > 0.8` → Telegram bot Lambda
   - `ALL signals` → Dashboard WebSocket
   - `asset = "SOL" AND signal = "BUY"` → Solana executor (future)
4. Each subscriber receives only matching events

### Why Not Simple Pub/Sub (SNS+SQS)?

With SNS, all subscribers receive all messages and must filter themselves. EventBridge does content-based filtering centrally — rules are declarative and manageable without modifying consumers.

### Why Not Direct WebSocket from Agent?

WebSocket is point-to-point and couples the agent to its consumers. Adding a new subscriber requires modifying the agent. With EventBridge, you add a rule — zero changes to the agent code.

---

## Decision 7: Observability — Two Layers

### The Problem

"Is my agent making good decisions?" and "Is my infrastructure efficient?" are different questions that need different tools.

### Layer 1: Agent Observability (LangFuse)

Strands SDK emits OpenTelemetry traces automatically. LangFuse ingests them and shows:
- Which tools the agent called, in what order
- Input/output of each tool call
- Token consumption per step
- Full reasoning chain
- Latency breakdown: how long on LLM vs tools vs network

This answers: "Why did the agent generate a SELL signal? Was it because of the RSI value or the news sentiment?"

### Layer 2: Infrastructure Observability (Prometheus + Grafana)

Monitors cluster-level metrics:
- GPU/Neuron utilization percentage
- Node scaling events (Karpenter provisions/terminates)
- vLLM inference latency per backend (GPU vs Neuron)
- Cost per node pool (ARM vs GPU vs Inferentia)
- Pod scheduling wait times

This answers: "Are we paying for idle GPUs? Is the Neuron backend slower than GPU? Should we shift more traffic to the cheaper backend?"

---

## Decision 8: Real Data vs Mock Data

### The Decision

Real data from Polymarket API for the demo.

### Risk Mitigation

- If the Polymarket API is down during the live demo, have cached responses as fallback in the MCP server
- Pre-record a video of the demo working as backup
- Test API connectivity before going on stage

### Why Real Data

The audience can verify the data is real. Showing a BTC prediction market that they can look up on their phones while watching the demo creates an "aha moment" that mocked data can't achieve.

---

## Non-Decisions (Explicitly Out of Scope)

These are things we intentionally did NOT include and why:

| Not Included | Why |
|---|---|
| **Swarm pattern** | The demo uses the Graph pattern (Vigía → Estratega → Mensajero) which provides deterministic routing. Swarm (dynamic agent handoffs) adds unpredictability that's unnecessary here. See `docs/agent-patterns.md`. |
| **Model training/fine-tuning** | We use pre-trained models. Training is a different talk. |
| **Amazon OpenSearch Service on EKS** | RAG is implemented locally with ChromaDB (in-process, no server needed). On EKS: Amazon OpenSearch Service (managed) + LiteLLM `/embeddings` endpoint — the same gateway already used for chat, no extra infra. The demo talks about the hardware abstraction story, not vector DB operations. |
| **Distributed processing (Ray/KubeRay)** | No massively parallel workloads in this demo. |
| **Advanced model serving (KServe)** | Would add abstraction that obscures the Kubernetes mechanics we want to teach. Mentioned as a "next step" in the talk. |
| **Service mesh (Istio)** | Not needed at this demo's scale. Relevant when adding business microservices beyond AI. |
| **Trade execution** | We generate signals, we don't execute. This is a demo, not a trading bot. |
