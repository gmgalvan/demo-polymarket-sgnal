# Orchestrating Intelligence

### Multi-Architecture LLM Serving on Amazon EKS

> Deploying GenAI shouldn't be a hardware headache. Whether you run on NVIDIA GPUs or AWS Inferentia, Amazon EKS is the ultimate orchestrator.

---

## What Is This?

A real-time trading signal agent for prediction markets (Polymarket) that demonstrates multi-architecture LLM serving on Amazon EKS.

The agent analyzes BTC, ETH, and SOL on 5-minute and 15-minute timeframes, generates BUY/SELL/HOLD signals with confidence scores, Expected Value (EV), and Kelly Criterion sizing, then distributes them to subscribers via Telegram, web dashboard, and more.

**The interesting part isn't the agent — it's that the agent doesn't know or care whether its brain runs on NVIDIA GPUs or AWS Inferentia.** EKS abstracts the hardware.

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Container Orchestration | Amazon EKS + Karpenter |
| Agent Framework | Strands Agents SDK |
| Model Serving | vLLM (CUDA + Neuron SDK) |
| Model Gateway | LiteLLM (primary), Envoy AI Gateway (alternative) |
| Reasoning Model | Qwen3-30B / Llama 3.1 70B (quantized) |
| Signal Distribution | Amazon EventBridge |
| Agent Observability | LangFuse (via OpenTelemetry) |
| Infra Observability | Prometheus + Grafana |

## Architecture

```
┌───────────────────────────────────────────────────────────────┐
│                   EKS Cluster (multi-arch)                     │
│                                                                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │
│  │ MCP:         │  │ MCP:         │  │ MCP:         │          │
│  │ Polymarket   │  │ Tech Analysis│  │ Web Search   │  ARM     │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  nodes    │
│         │                │                 │                   │
│  Watchdog (asyncio) ─────────────────────────────────  ARM    │
│  triggers on candle_close / volatility_spike          node    │
│         │                                                      │
│  ┌──────┴──────────────────────────────────────────┐          │
│  │           Strands Graph                           │  ARM    │
│  │  Strategist (LLM) → [+EV?] → Broadcaster         │  node   │
│  │  Strategist uses MCP tools above ↑                │         │
│  │  Broadcaster: EV/Kelly math, _emit() — no LLM     │         │
│  └──────────────────────┬───────────────────────────┘          │
│                         │                                      │
│                   LiteLLM Gateway                      ARM     │
│                    ┌────┴────┐                         node    │
│                    ▼         ▼                                  │
│              ┌──────────┐ ┌──────────┐                         │
│              │   vLLM   │ │   vLLM   │  Accelerator            │
│              │  (GPU)   │ │ (Neuron) │  nodes                  │
│              └──────────┘ └──────────┘  (only for inference)   │
│                                                                │
└───────────────────────────┬────────────────────────────────────┘
                            │
                      EventBridge
                            │
                ┌───────────┼───────────┼───────────┐
                ▼           ▼           ▼           ▼
           Telegram    Dashboard    Email    (Solana)
```

## Agent System

The Strands Graph mixes LLM agents and deterministic nodes — not every node needs a model:

| Component | Type | LLM? | Role |
|-----------|------|------|------|
| **Watchdog** | Pure asyncio | ❌ | Monitors WebSockets 24/7, triggers graph on candle close or volatility spike |
| **Strategist** | Strands `Agent` | ✅ Qwen3-30B / Llama 70B | Calls MCP tools, reasons about data, emits GO/NO_GO with probability |
| **Broadcaster** | `MultiAgentBase` (FunctionNode) | ❌ | Calculates EV/Kelly from Strategist output, emits signal |
| **Context Analyst** | Strands `Agent` | ✅ Llama 3.1 8B | Background agent — feeds vector DB for RAG (Phase 4) |

Only the Strategist and Context Analyst need GPU/Inferentia. Everything else runs on ARM (~$0.04/hr). See `docs/agent-patterns.md` for full implementation details.

## Why?

This is the companion demo for the talk of the same name. It proves three things:

1. **You can abstract the hardware.** Configure EKS to seamlessly schedule workloads across different chip architectures.
2. **You can connect the dots.** Use Device Plugins to expose silicon, MCP servers to connect agents to data, and LiteLLM to unify access to models.
3. **You can ship it.** Kubernetes manifests bring your AI agents to life — regardless of the chip underneath.

## Cost Story

Only 2 out of 14 components need expensive GPU or Inferentia hardware. The rest run on ARM nodes (~$0.04/hr) or serverless. Match the hardware to the workload.

| Node Type | Hourly Cost | What Runs Here |
|-----------|------------|---------------|
| ARM (Graviton) | ~$0.04/hr | Agent, MCP servers, gateway, observability |
| GPU (g5.xlarge) | ~$1.01/hr | vLLM with CUDA |
| Inferentia (inf2.xlarge) | ~$0.76/hr | vLLM with Neuron SDK |

## Repository Structure

```
├── CLAUDE.md              # AI assistant context
├── README.md              # You are here
├── docs/
│   ├── architecture.md    # Architecture decisions and rationale
│   ├── components.md      # Component descriptions and responsibilities
│   ├── models.md          # Model selection, quantization, compilation
│   ├── agent-patterns.md  # Multi-agent Strands patterns (Graph, Vigía, FunctionNode)
│   ├── talk-outline.md    # Talk narrative and timing
│   └── agent_flow.mermaid # Agent flow diagram (Vigía → Estratega → Mensajero)
├── infra/                 # EKS cluster, node pools, device plugins
├── platform/              # LiteLLM gateway, vLLM deployments, observability
├── agents/                # Strands orchestrator agent and native tools
├── services/              # MCP servers (Polymarket, TA, web search)
├── distribution/          # EventBridge rules and subscriber functions
└── demo/                  # Demo scripts and utilities
```

## Local Runbook (Current)

### 1) Setup

```bash
uv venv
uv pip install -e ".[dev]"
cp .env.example .env
```

Required in `.env`:
- `ANTHROPIC_API_KEY`
- `TAVILY_API_KEY` (recommended for web-search MCP)

### 2) Start MCP servers (for `--use-mcp true`)

```bash
docker compose up -d
docker compose ps
```

### 3) Run the loop

Mock loop (no network required):

```bash
./.venv/bin/python demo/run_watchdog_loop.py --mode mock --max-events 3 --use-mcp false
```

Live WebSocket loop (Binance + Polymarket, MCP enabled):

```bash
./.venv/bin/python demo/run_watchdog_loop.py --mode websocket --use-mcp true --max-events 1
```

Long-running live mode:

```bash
./.venv/bin/python demo/run_watchdog_loop.py --mode websocket --use-mcp true
```

### 4) Log tracking (services + agent)

Recommended terminal split:

Terminal A (MCP services):

```bash
docker compose up -d
docker compose ps
```

Terminal B (follow MCP logs):

```bash
docker compose logs -f polymarket technical-analysis web-search
```

Terminal C (run agent loop + persist logs):

```bash
mkdir -p logs
./.venv/bin/python demo/run_watchdog_loop.py --mode websocket --use-mcp true 2>&1 | tee -a logs/agent-loop.log
```

Useful log filters:

```bash
rg -n "\\[Watchdog\\]|\\[Strategist\\]|\\[Graph\\]|SIGNAL EMITTED" logs/agent-loop.log
```

Export MCP logs to file:

```bash
docker compose logs --no-color > logs/mcp-services.log
```

### 5) Polymarket odds source

- If `POLYMARKET_WS_URL` is set, watchdog uses Polymarket live WS.
- If `POLYMARKET_AUTO_SUBSCRIBE=true`, watchdog auto-selects an active BTC market and rotates subscriptions on reconnect.
- If WS is unavailable, it falls back to `POLYMARKET_DEFAULT_ODDS`.

### 6) Quick troubleshooting

- `POLYMARKET_WS_URL is not set. Using default odds=2.0.`
  Set `POLYMARKET_WS_URL` in `.env`.
- `Status.COMPLETED nodes=1/2`
  Strategist returned `NO_GO`; broadcaster was intentionally skipped.
- `Status.FAILED`
  Check `[Graph] failed_node=... error=...` in logs.
- MCP tools not being called
  Ensure containers are up and run with `--use-mcp true`.

## Status

✅ **Implemented locally through Phase 3**

- Phase 1: Graph core
- Phase 2: MCP servers
- Phase 3: Watchdog + full loop (mock + websocket)
- Phase 4 (RAG + vector DB abstraction) is planned in `specs/PLAN.md`

## References

- [Guidance for Scalable Model Inference and Agentic AI on Amazon EKS](https://aws-solutions-library-samples.github.io/compute/scalabale-model-inference-and-agentic-ai-on-amazon-eks.html)
- [AI on EKS — AWS Labs](https://awslabs.github.io/ai-on-eks/)
- [Strands Agents SDK](https://strandsagents.com)
- [Envoy AI Gateway on EKS](https://awslabs.github.io/ai-on-eks/docs/blueprints/gateways/envoy-gateway)

## Disclaimer

This is a demo for educational purposes. It is NOT a production trading system. Do not use generated signals for real financial decisions.
