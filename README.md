# Orchestrating Intelligence

### Multi-Architecture LLM Serving on Amazon EKS

![AI Stack del Reino Champiñón](docs/intro.png)

> Deploying GenAI shouldn't be a hardware headache. Whether you run on NVIDIA GPUs or AWS Inferentia, Amazon EKS is the ultimate orchestrator.

---

## What Is This?

A real-time trading signal agent for prediction markets (Polymarket) that demonstrates multi-architecture LLM serving on Amazon EKS.

The agent monitors BTC via Coinbase 5-minute candles, predicts UP or DOWN over the current 15-minute Polymarket window, and generates GO/NO_GO signals with confidence scores, Expected Value (EV), and Kelly Criterion sizing. Signals are distributed to subscribers via Telegram, web dashboard, and more.

**The interesting part isn't the agent — it's that the agent doesn't know or care whether its brain runs on NVIDIA GPUs or AWS Inferentia.** EKS abstracts the hardware.

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Container Orchestration | Amazon EKS + Karpenter |
| Agent Framework | Strands Agents SDK |
| Model Serving | vLLM (CUDA + Neuron SDK) |
| Model Gateway | LiteLLM (primary), Envoy AI Gateway (alternative) |
| Reasoning Model | Qwen3-30B / Llama 3.1 70B (quantized) |
| Vector Store (local) | ChromaDB in-process (all-MiniLM-L6-v2 embeddings via ONNX) |
| Vector Store (EKS) | Amazon OpenSearch Service + LiteLLM `/embeddings` endpoint |
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

## Post-EKS: Console Access Fix

After creating EKS, if AWS Console shows:

`Your current IAM principal doesn't have access to Kubernetes objects on this cluster`

run this checklist:

```bash
# 1) Verify CLI principal (local shell)
aws sts get-caller-identity --query Arn --output text

# 2) Verify Console principal (CloudShell in the SAME browser session)
aws sts get-caller-identity --query Arn --output text
```

Important:
- If CloudShell shows `arn:aws:iam::<account-id>:root`, your browser is logged in as root.
- EKS access entries are principal-specific. Access granted to `user/infra` does not grant access to `root`.

Grant EKS access entry + admin policy to the active principal:

```bash
aws eks create-access-entry \
  --cluster-name 352-demo-dev-eks \
  --region us-east-1 \
  --principal-arn <PRINCIPAL_ARN>

aws eks associate-access-policy \
  --cluster-name 352-demo-dev-eks \
  --region us-east-1 \
  --principal-arn <PRINCIPAL_ARN> \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

Validate:

```bash
aws eks describe-access-entry \
  --cluster-name 352-demo-dev-eks \
  --region us-east-1 \
  --principal-arn <PRINCIPAL_ARN>

aws eks list-associated-access-policies \
  --cluster-name 352-demo-dev-eks \
  --region us-east-1 \
  --principal-arn <PRINCIPAL_ARN>
```

Terraform-managed access is documented in:
- `infrastructure/lv-2-core-compute/eks/README.md`

## Full Cleanup

For full teardown in safe order (`Kubernetes -> lv-3 -> lv-2 -> lv-0 -> ECR -> Docker local`), use:

- `docs/CLEANUP.md`

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
├── docs/                  # Architecture docs, talk materials, diagrams
├── infrastructure/        # Terraform IaC (networking, IAM, EKS, cluster services)
├── kubernetes/            # K8s manifests (Inferentia, GPU, model storage examples)
├── specs/                 # Planning docs
└── demo-polymarket/       # Application code (agent + services + demo scripts)
    ├── pyproject.toml     # Python package config
    ├── docker-compose.yml # Local MCP servers + ChromaDB
    ├── agents/
    │   ├── strategist/    # Reasoning agent + prompts + RAG tool
    │   ├── broadcaster/   # Deterministic EV/Kelly FunctionNode
    │   ├── watchdog/      # asyncio WebSocket monitor
    │   └── context_analyst/ # Background RAG agent + ingest CLI
    ├── services/
    │   ├── polymarket/        # Polymarket MCP server
    │   ├── technical_analysis/# TA indicators MCP server
    │   ├── web_search/        # Tavily web search MCP server
    │   └── vectorstore/       # VectorStore abstraction (Chroma/OpenSearch)
    ├── tests/             # pytest test suite
    └── demo/              # Demo scripts (trigger_local, watchdog loop)
```

## Local Runbook (Current)

### 1) Setup

```bash
cd demo-polymarket
uv venv
uv pip install -e ".[dev]"   # installs package in editable mode — required to avoid ModuleNotFoundError
cp .env.example .env
```

Required in `.env`:
- `ANTHROPIC_API_KEY`
- `TAVILY_API_KEY` (recommended for web-search MCP)

### 2) Start MCP servers + ChromaDB

```bash
cd demo-polymarket
docker compose up -d
docker compose ps
```

Services started: `polymarket` (8001), `technical-analysis` (8002), `web-search` (8003), `chromadb` (8004).

### 3) Ingest context into vector DB (Phase 4 / RAG)

All python commands below assume you are in `demo-polymarket/` and the venv is active.

```bash
cd demo-polymarket
source ../.venv/bin/activate   # venv lives at repo root

# Option A — fetch REAL BTC news from Tavily (requires TAVILY_API_KEY in .env)
python agents/context_analyst/ingest_context.py --fetch-news

# Option B — ingest built-in sample contexts (works without API keys)
python agents/context_analyst/ingest_context.py --sample

# Option C — ingest custom text
python agents/context_analyst/ingest_context.py --asset BTC --source news --text "BTC broke $85k..."
```

> **Hybrid memory**: `--fetch-news` pulls real Tavily articles into ChromaDB as historical context. Once the agent loop is running with `USE_RAG=true`, every GO signal is automatically ingested as a `signal_log` entry — the system builds memory of what setups actually worked.

### 4) Run the agent

**Quick single shot** (hardcoded scenario, no arguments needed):

```bash
# Minimal — no MCP, no RAG
python demo/trigger_local.py

# With RAG (reads from ChromaDB)
USE_RAG=true python demo/trigger_local.py
```

**Watchdog loop** (continuous, mock data):

```bash
python demo/run_watchdog_loop.py --mode mock --max-events 3 --use-mcp false

# With RAG
USE_RAG=true python demo/run_watchdog_loop.py --mode mock --max-events 3 --use-mcp false
```

**Live WebSocket loop** (real Coinbase + Polymarket):

```bash
USE_RAG=true python demo/run_watchdog_loop.py --mode websocket --use-mcp true

# Optional: force Binance fallback provider
MARKET_DATA_PROVIDER=binance USE_RAG=true python demo/run_watchdog_loop.py --mode websocket --use-mcp true
```

### 5) Log tracking (services + agent)

Recommended terminal split (all from `demo-polymarket/`):

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
python demo/run_watchdog_loop.py --mode websocket --use-mcp true 2>&1 | tee -a logs/agent-loop.log
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
- Set `POLYMARKET_SLUG_PATTERN=btc-updown-15m` to auto-discover rolling 15-minute BTC Up/Down markets via computed slug. The refresh interval is auto-computed (window × 0.9 = 810s for 15-minute markets).
- If `POLYMARKET_AUTO_SUBSCRIBE=true` (and no slug pattern), watchdog falls back to searching via Gamma `/public-search` API.
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

✅ **Implemented locally through Phase 4**

- Phase 1: Graph core (Strategist → Broadcaster)
- Phase 2: MCP servers (Polymarket, Technical Analysis, Web Search)
- Phase 3: Watchdog + full loop (mock + websocket)
- Phase 4: RAG + Context Analyst + ChromaDB vector store

## References

- [Guidance for Scalable Model Inference and Agentic AI on Amazon EKS](https://aws-solutions-library-samples.github.io/compute/scalabale-model-inference-and-agentic-ai-on-amazon-eks.html)
- [AI on EKS — AWS Labs](https://awslabs.github.io/ai-on-eks/)
- [Strands Agents SDK](https://strandsagents.com)
- [Envoy AI Gateway on EKS](https://awslabs.github.io/ai-on-eks/docs/blueprints/gateways/envoy-gateway)

## Disclaimer

This is a demo for educational purposes. It is NOT a production trading system. Do not use generated signals for real financial decisions.
