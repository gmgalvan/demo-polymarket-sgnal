# Guardrails & Quality Monitoring for GenAI

This document describes options for adding quality monitoring and guardrails
to the GenAI inference pipeline. These are **optional enhancements** beyond
the base observability stack (Prometheus, Grafana, Loki, OTel, LangFuse).

## 1. LLM Output Quality Monitoring

### LangFuse Evaluations (Recommended — already deployed)

LangFuse supports **evaluation scores** attached to traces. Use this to track
output quality over time without additional infrastructure:

```python
# In the Strands agent or post-processing hook
from langfuse import Langfuse

langfuse = Langfuse()
trace = langfuse.trace(name="strategist-signal")
trace.score(name="signal_confidence", value=0.82)
trace.score(name="ev_positive", value=1)  # binary: 1=positive EV, 0=negative
```

### LLM-as-a-Judge (Async Sampling)

For deeper quality assessment, sample 1-10% of responses and evaluate them
asynchronously with a judge model:

1. **Collect**: The OTel Collector already captures all traces. Configure a
   tail-based sampler to export 5% of traces to a quality-evaluation queue.
2. **Judge**: A lightweight Lambda or K8s CronJob calls a judge model
   (e.g., Claude via LiteLLM) with the original prompt + response + rubric.
3. **Score**: Write evaluation scores back to LangFuse via API.

Prometheus metrics to expose:
- `genai_quality_score` (histogram) — judge scores per model/prompt type
- `genai_hallucination_detected_total` (counter) — flagged hallucinations
- `genai_guardrail_blocked_total` (counter) — blocked responses

### Custom Prometheus Metrics

Add to the Strands agent process (Python `prometheus_client`):

```python
from prometheus_client import Counter, Histogram, start_http_server

signal_confidence = Histogram(
    "polymarket_signal_confidence",
    "Confidence score of generated signals",
    buckets=[0.5, 0.6, 0.7, 0.8, 0.9, 0.95, 1.0],
)
signal_ev = Histogram(
    "polymarket_signal_ev_pct",
    "Expected value percentage of generated signals",
    buckets=[-10, -5, 0, 5, 10, 15, 20, 30, 50],
)
signal_decision = Counter(
    "polymarket_signal_decision_total",
    "Count of GO/NO_GO decisions",
    ["decision"],  # labels: go, no_go
)
```

The MCP servers PodMonitor already configured in this module will scrape
these metrics if the agent pod has the correct labels.

## 2. Guardrails Options

### Option A: NVIDIA NeMo Guardrails

Best for: Topical guardrails, jailbreak prevention, output validation.

- Deploy as a sidecar or separate service in front of LiteLLM
- Define rails in Colang (NVIDIA's guardrail language)
- Integrates with vLLM and LiteLLM

```yaml
# Example Colang rail for the trading signal agent
define user ask about non-crypto topics
  "What's the weather?"
  "Tell me a joke"

define flow
  user ask about non-crypto topics
  bot refuse and redirect
  "I'm a crypto market analyst. I can only help with BTC prediction signals."
```

### Option B: Guardrails AI

Best for: Structured output validation, hallucination detection.

- Python library that wraps LLM calls with validators
- Can validate JSON schema compliance of signal output
- Supports custom validators for domain-specific rules

```python
from guardrails import Guard
from guardrails.hub import ValidJson, ToxicLanguage

guard = Guard().use_many(
    ValidJson(on_fail="reask"),
    ToxicLanguage(on_fail="filter"),
)
```

### Option C: AWS Bedrock Guardrails (if using Bedrock)

Best for: AWS-native deployments using Bedrock as an alternative to self-hosted vLLM.

- Content filters (hate, violence, sexual, misconduct)
- Denied topics
- Word filters
- PII detection and redaction

### Recommendation for This Demo

For the talk demo, **LangFuse evaluations + custom Prometheus metrics** provide
the best value with minimal additional infrastructure:

1. LangFuse is already deployed — just instrument the agent code
2. Custom Prometheus metrics feed into existing Grafana dashboards
3. No additional services to manage

For production, add NeMo Guardrails as a sidecar to the LiteLLM gateway.

## 3. Cost Monitoring

LangFuse automatically tracks token usage per model. For infrastructure cost:

- **Kubecost** or **OpenCost** — Deploy as a Helm release in the monitoring
  namespace to get per-namespace, per-pod cost breakdowns
- **Karpenter metrics** — Already scraped by Prometheus. Create a dashboard
  showing node pool costs: `karpenter_nodepools_usage{resource_type="cpu"}`
- **DCGM + node cost** — Correlate GPU utilization with hourly instance cost
  to calculate cost-per-token

```promql
# Estimated hourly cost per GPU node (assuming g6.xlarge at $1.006/hr)
count(DCGM_FI_DEV_GPU_UTIL) * 1.006
```
