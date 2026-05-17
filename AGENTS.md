# AGENTS.md

This file gives coding agents the minimum project context needed to work safely and efficiently in this repository.

## Project Summary

This repo contains a demo for the talk **"Orchestrating Intelligence: Multi-Architecture LLM Serving on Amazon EKS"**.

The application is a **real-time Polymarket trading signal agent**:

- Watches BTC market data and short-horizon prediction markets
- Uses an LLM strategist plus deterministic logic
- Produces `GO` / `NO_GO` signals with confidence, EV, and Kelly sizing
- Demonstrates that the agent layer stays the same while inference can run on different hardware behind EKS

The core point of the project is **infrastructure abstraction**, not automated trading.

## Current State

- Local phases are implemented
- EKS deployment is still the target deployment story
- The codebase appears to have been **renamed/restructured**

Important path note:

- Older docs still refer to `demo-polymarket/`
- The current application code in this repo lives under `polymarket/`
- Kubernetes examples currently live under `examples/kubernetes/`

When editing docs or commands, prefer the **real paths in the repository today** unless you are intentionally updating old references.

## Architecture At A Glance

There are three practical layers:

1. **Platform**
   - Terraform under `infrastructure/`
   - EKS + Karpenter
   - Multi-arch compute: ARM for lightweight services, GPU / Inferentia for inference

2. **Agent system**
   - `polymarket/agents/watchdog/`: async event loop that detects trigger conditions
   - `polymarket/agents/strategist/`: LLM reasoning node
   - `polymarket/agents/broadcaster/`: deterministic EV/Kelly/signal emission
   - `polymarket/agents/context_analyst/`: RAG ingestion and context enrichment
   - `polymarket/agents/graph.py`: graph wiring and conditional routing

3. **Support services**
   - `polymarket/services/polymarket/`: market data MCP server
   - `polymarket/services/technical_analysis/`: TA MCP server
   - `polymarket/services/web_search/`: search/news MCP server
   - `polymarket/services/vectorstore/`: Chroma/OpenSearch abstraction

## Key Engineering Principles

- Keep **hardware concerns out of agent logic**
- Keep **math and deterministic rules outside the LLM**
- Use MCP/services for reusable external-data capabilities
- Use the graph for orchestration, not for hiding business logic
- Preserve the demo story: the app should work the same whether the backing model is direct Anthropic locally or LiteLLM/vLLM on EKS

## Source Of Truth Files

Read these first before making non-trivial changes:

- `README.md`: top-level demo overview
- `CLAUDE.md`: detailed project context and intent
- `docs/architecture.md`: why the system is designed this way
- `docs/running-locally.md`: actual local execution flow
- `polymarket/agents/config.py`: runtime switches and environment model
- `polymarket/pyproject.toml`: package/test config

## Working Areas

### Python app

- Root package area: `polymarket/`
- Tests: `polymarket/tests/`
- Demo entry points: `polymarket/demo/`
- Package name in `pyproject.toml`: `polymarket-signal-agent`

### Infrastructure

- Terraform stacks are grouped by level under `infrastructure/lv-*`
- Reusable Terraform modules live in `infrastructure/modules/`
- Helper scripts live in `infrastructure/scripts/`

### Examples

- Kubernetes manifests and deployment examples live under `examples/kubernetes/`
- Standalone examples live under `examples/standalone/`

## Local Setup

From the repository root:

```bash
cd polymarket
uv venv
uv pip install -e ".[dev]"
cp ../.env.example .env
```

Notes:

- The editable install matters because imports use top-level packages like `agents` and `services`
- Some older docs mention `demo-polymarket`; in this repo use `polymarket`

## Common Commands

Run from `polymarket/` unless noted otherwise.

### Tests

```bash
pytest
pytest tests/test_graph.py -v -s
pytest tests/test_watchdog.py -v
```

Some tests are integration-style and may require environment variables such as `ANTHROPIC_API_KEY`.

### Demo runs

```bash
python demo/trigger_local.py
USE_RAG=true python demo/trigger_local.py
python demo/run_watchdog_loop.py --mode mock --max-events 3
```

### Local services

```bash
docker compose up -d
docker compose ps
```

## Environment Model

The main runtime split is in `polymarket/agents/config.py`.

Local default:

- `MODEL_PROVIDER=anthropic`
- direct Anthropic access via `ANTHROPIC_API_KEY`

EKS-oriented mode:

- `MODEL_PROVIDER=litellm_proxy`
- `LITELLM_API_BASE` points to LiteLLM
- LiteLLM routes to vLLM backends on GPU or Inferentia

Feature flags to know:

- `USE_MCP`
- `USE_RAG`
- `VECTOR_BACKEND`
- `USE_LMSR`

## Guardrails For Agents

- Do not reintroduce path assumptions from the old `demo-polymarket/` layout without checking the repo first
- Prefer small, targeted edits over broad doc rewrites
- If you change docs, keep commands consistent with the current repo structure
- If you change agent behavior, verify whether the change belongs in:
  - strategist reasoning
  - broadcaster deterministic logic
  - watchdog trigger logic
  - MCP/service layer
- Keep deterministic finance/math logic outside the LLM path whenever possible
- Avoid coupling application code to a specific accelerator or serving backend

## Recommended Change Workflow

1. Read the nearest docs and the affected module
2. Check `polymarket/tests/` for expected behavior
3. Make the smallest coherent change
4. Run the narrowest relevant test first
5. Update docs if behavior, paths, or commands changed

## Good First File Map

- Graph flow: `polymarket/agents/graph.py`
- Runtime config: `polymarket/agents/config.py`
- Strategist: `polymarket/agents/strategist/agent.py`
- Broadcaster: `polymarket/agents/broadcaster/node.py`
- Watchdog: `polymarket/agents/watchdog/watchdog.py`
- RAG tool: `polymarket/agents/strategist/tools_rag.py`
- Context ingestion: `polymarket/agents/context_analyst/ingest_context.py`

## Non-Goals

- This is not a production trading system
- This is not a training pipeline
- This is not primarily a brokerage/execution bot

Optimize for the demo story: **agent orchestration, hardware abstraction, and clear separation between LLM reasoning and deterministic execution**.
