# Observability Stack

> **Status:** Terraform modules implemented. Deployment pending (requires EKS cluster from lv-2).

## Overview

The observability stack provides three pillars of visibility into the GenAI platform:

1. **Metrics** — Prometheus + Grafana + hardware-specific exporters (DCGM, Neuron)
2. **Logs** — Fluent Bit + Loki (centralized, queryable from Grafana)
3. **Traces** — OpenTelemetry Collector + LangFuse (distributed tracing + LLM-specific observability)

Everything runs on ARM (Graviton) core nodes except the hardware exporters, which run as DaemonSets on their respective accelerator nodes.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                        ARM / Graviton Nodes                          │
│                                                                      │
│  ┌─────────────────┐  ┌───────────┐  ┌───────────────┐             │
│  │   Prometheus     │  │  Grafana   │  │ Alertmanager  │             │
│  │  (kube-prom-     │  │ (dashboards│  │  (routing)    │             │
│  │   stack)         │◄─│  + Loki DS)│  │               │             │
│  └────────┬─────┬──┘  └───────────┘  └───────────────┘             │
│           │     │                                                    │
│           │     │   ┌──────────────┐  ┌───────────────────┐         │
│           │     │   │    Loki      │  │  OTel Collector    │         │
│           │     │   │ (log storage)│  │ (OTLP → LangFuse  │         │
│           │     │   └──────┬───────┘  │  + span metrics)  │         │
│           │     │          │          └─────────┬─────────┘         │
│           │     │          │                    │                    │
│           │     │   ┌──────┴───────┐  ┌────────┴──────────┐        │
│           │     │   │  Fluent Bit  │  │     LangFuse       │        │
│           │     │   │ (DaemonSet   │  │ (LLM traces,       │        │
│           │     │   │  ALL nodes)  │  │  token usage,      │        │
│           │     │   └──────────────┘  │  prompt history)   │        │
│           │     │                     └────────────────────┘        │
│           │     │                                                    │
│  ┌────────┴─────┴───────────────────────────────────────┐           │
│  │               prometheus-adapter                      │           │
│  │  (custom metrics → HPA: vLLM queue depth, GPU util)   │           │
│  └───────────────────────────────────────────────────────┘           │
└──────────────────────────────────────────────────────────────────────┘

┌────────────────────────┐     ┌────────────────────────────┐
│   GPU Nodes (g6/g5)    │     │ Inferentia Nodes (inf2)    │
│                        │     │                            │
│  ┌──────────────────┐  │     │  ┌──────────────────────┐  │
│  │  DCGM Exporter   │  │     │  │   Neuron Monitor     │  │
│  │  (nvidia.com/gpu │  │     │  │  (neuron-monitor -p)  │  │
│  │   metrics)       │  │     │  │                       │  │
│  └──────────────────┘  │     │  └───────────────────────┘  │
│                        │     │                            │
│  ┌──────────────────┐  │     │  ┌──────────────────────┐  │
│  │  Fluent Bit      │  │     │  │  Fluent Bit          │  │
│  └──────────────────┘  │     │  └──────────────────────┘  │
└────────────────────────┘     └────────────────────────────┘
```

---

## Components

### Prometheus + Grafana (kube-prometheus-stack)

**Namespace:** `monitoring`

Deploys Prometheus, Grafana, Alertmanager, kube-state-metrics, and node-exporter as a single Helm release.

**Configuration:**

| Setting | Value | Rationale |
|---------|-------|-----------|
| `scrapeInterval` | 30s | Balance between freshness and cardinality for a demo cluster |
| `evaluationInterval` | 30s | Match scrape interval for consistent alerting |
| `scrapeTimeout` | 10s | Default — prevents slow targets from blocking scrape cycles |
| `retention` | 5h | Short retention for demo; increase for production |
| PVC | 50Gi | Sufficient for 5h retention with all exporters |
| `serviceMonitorSelectorNilUsesHelmValues` | false | Discover ALL ServiceMonitors, not just those from the Helm release |

Grafana is pre-configured with:
- Default K8s dashboards (compute resources, node exporter)
- Loki as a log data source
- OTel Collector as a trace data source
- Sidecar that auto-loads dashboards from ConfigMaps with label `grafana_dashboard: "1"`

### prometheus-adapter

Exposes Prometheus metrics as Kubernetes custom metrics for HPA autoscaling. Pre-configured rules:
- `vllm_requests_waiting` — scale vLLM replicas based on queue depth
- `vllm_requests_running` — scale based on active request count

---

### NVIDIA DCGM Exporter (GPU Nodes)

**Runs on:** GPU nodes only (`workload=gpu` + `nvidia.com/gpu` toleration)

Exports metrics from the NVIDIA Data Center GPU Manager via a DaemonSet.

**Key metrics:**

| Metric | What it measures |
|--------|-----------------|
| `DCGM_FI_DEV_GPU_UTIL` | GPU compute utilization (%) |
| `DCGM_FI_DEV_FB_USED` / `DCGM_FI_DEV_FB_FREE` | Framebuffer (VRAM) memory |
| `DCGM_FI_DEV_GPU_TEMP` | GPU die temperature (°C) |
| `DCGM_FI_DEV_POWER_USAGE` | Power draw (Watts) |
| `DCGM_FI_DEV_SM_CLOCK` | Streaming multiprocessor clock (MHz) |
| `DCGM_FI_DEV_XID_ERRORS` | Xid hardware/driver errors |

**Alerting rules (`gpu.rules`):**

| Alert | Condition | Severity |
|-------|-----------|----------|
| `GPUMemoryUsageHigh` | VRAM > 90% for 5m | warning |
| `GPUHighUtilization` | GPU > 95% for 5m | warning |
| `GPULowUtilization` | GPU < 20% for 15m | info |
| `GPUTemperatureTooHigh` | > 85°C for 3m | critical |
| `GPUXidErrorDetected` | Xid ≠ 0 for 1m | critical |

**Reference:** [NVIDIA DCGM Exporter](https://github.com/NVIDIA/dcgm-exporter)

---

### AWS Neuron Monitor (Inferentia/Trainium Nodes)

**Runs on:** Inferentia/Trainium nodes only (`workload=neuron` + `aws.amazon.com/neuron` toleration)

AWS Inferentia and Trainium chips do NOT use NVIDIA DCGM. They have their own monitoring tool: `neuron-monitor`, part of the Neuron SDK. We deploy it as a DaemonSet that exposes Prometheus metrics via the `-p` flag.

The DaemonSet mounts `/run/neuron` from the host to access the Neuron runtime socket and runs with `hostPID: true` for device inspection.

**Key metrics:**

| Metric | What it measures |
|--------|-----------------|
| `neuroncore_utilization` | Per-NeuronCore compute utilization (%) |
| `neuron_runtime_memory_used_bytes` | Device (HBM) memory used |
| `neuron_runtime_memory_total_bytes` | Total device (HBM) memory |
| `neuron_runtime_vcpu_usage` | NeuronCore vCPU utilization |
| `neuroncore_memory_usage_model_shared_scratchpad` | Memory for model shared scratchpad |
| `neuron_execution_latency` | Inference execution latency (ms) |
| `neuron_execution_errors_total` | Runtime execution error counter |
| `neuron_instance_info` | Hardware metadata (instance type, core count) |

**Alerting rules (`neuron.rules`):**

| Alert | Condition | Severity |
|-------|-----------|----------|
| `NeuronCoreHighUtilization` | > 95% for 5m | warning |
| `NeuronCoreLowUtilization` | < 10% for 15m | info |
| `NeuronExecutionErrors` | error rate > 0 for 2m | critical |
| `NeuronMemoryUsageHigh` | HBM > 90% for 5m | warning |
| `NeuronMemoryUsageCritical` | HBM > 98% for 2m | critical |
| `NeuronExecutionLatencyHigh` | > 5000ms for 5m | warning |

**Reference:** [Neuron Monitor User Guide](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/tools/neuron-sys-tools/neuron-monitor-user-guide.html)

---

### ServiceMonitors & PodMonitors

Each component that exposes `/metrics` gets a dedicated monitor CR so Prometheus discovers it automatically.

| Monitor | Type | Selector | Port | Target |
|---------|------|----------|------|--------|
| vLLM | ServiceMonitor | `app.kubernetes.io/name=vllm` | `http` (8000) | All vLLM Services |
| vLLM (legacy) | PodMonitor | `app` exists, `app.kubernetes.io/name` absent | `http` (8000) | Pods with old-style `app: vllm-*` labels |
| LiteLLM | ServiceMonitor | `app.kubernetes.io/name=litellm` | `http` (4000) | LiteLLM gateway |
| KServe | PodMonitor | `serving.kserve.io/inferenceservice` Exists | `http1` (8080) | KServe InferenceService pods |
| MCP Servers | PodMonitor | `app.kubernetes.io/part-of=polymarket-signal` + `component=mcp-server` | `http` | Polymarket, TA, Web Search |
| Fluent Bit | ServiceMonitor | (auto from Helm) | 2020 | Log collector health |
| OTel Collector | ServiceMonitor | (auto from Helm) | 8889 | Span metrics |

**Label convention for new manifests:**

```yaml
labels:
  app.kubernetes.io/name: vllm          # ServiceMonitor matches this
  app.kubernetes.io/instance: vllm-gpu-qwen25
  app.kubernetes.io/component: inference
  app.kubernetes.io/part-of: polymarket-signal
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8000"
  prometheus.io/path: "/metrics"
```

All existing manifests in `kubernetes/examples/` have been updated with these labels.

---

### vLLM Metrics & Alerting

vLLM natively exposes `/metrics` on port 8000 with LLM-specific Prometheus metrics.

**Key metrics monitored:**

| Metric | What it measures |
|--------|-----------------|
| `vllm:time_to_first_token_seconds` | TTFT — latency until first token is streamed |
| `vllm:time_per_output_token_seconds` | TPOT / ITL — inter-token latency |
| `vllm:e2e_request_latency_seconds` | End-to-end request duration |
| `vllm:prompt_tokens_total` | Cumulative prompt tokens processed |
| `vllm:generation_tokens_total` | Cumulative generation tokens produced |
| `vllm:num_requests_waiting` | Requests queued (waiting for a slot) |
| `vllm:num_requests_running` | Requests currently being processed |

**Alerting rules (`llm.rules`):**

| Alert | Condition | Severity |
|-------|-----------|----------|
| `VLLMHighTimePerOutputToken` | TPOT P95 >= 300ms for 5m | warning |
| `VLLMHighE2ELatency` | E2E P95 >= 30s for 5m | warning |
| `VLLMHighTimeToFirstToken` | TTFT P95 >= 10s for 5m | warning |
| `VLLMRequestQueueGrowing` | Waiting > 10 for 3m | warning |
| `VLLMRequestQueueCritical` | Waiting > 50 for 1m | critical |
| `VLLMNoRequestsProcessed` | 0 completions + running > 0 for 5m | critical |
| `VLLMHighTokenRate` | Generation > 5000 tok/s for 10m | info |

---

### Loki + Fluent Bit (Logging)

**Loki** runs in single-binary mode on an ARM node with 10Gi persistence. No microservices deployment needed for a demo cluster.

**Fluent Bit** runs as a DaemonSet on ALL nodes (ARM, GPU, Inferentia) via `tolerations: [{operator: Exists}]`. It collects container logs from `/var/log/containers/` and forwards them to Loki with Kubernetes metadata labels (namespace, pod, container).

Grafana queries Loki via the pre-configured data source. The GenAI Overview dashboard includes a "Recent vLLM Logs" panel that filters by `container=~"vllm.*"`.

---

### OpenTelemetry Collector (Tracing)

**Namespace:** `tracing`

Central hub for distributed traces. Receives OTLP traces (gRPC on 4317, HTTP on 4318) from:

| Source | How it sends traces |
|--------|-------------------|
| vLLM | `--otlp-traces-endpoint` CLI flag + `OTEL_SERVICE_NAME` env var |
| Strands agent | Built-in OpenTelemetry SDK support |
| LiteLLM | `OTEL_EXPORTER_OTLP_ENDPOINT` env var |
| MCP servers | Manual instrumentation (optional) |

**Pipeline:**

```
  OTLP receivers → memory_limiter → resource (add cluster.name) → batch
       │
       ├──→ LangFuse (OTLP export)     ← prompt/response tracing
       ├──→ spanmetrics connector       ← RED metrics (Rate, Errors, Duration)
       │         └──→ Prometheus export ← span metrics as Prometheus gauges
       └──→ debug (stdout, basic)       ← development aid
```

The `spanmetrics` connector generates Prometheus metrics from trace spans, giving latency histograms per service without additional instrumentation.

---

### LangFuse (LLM Observability)

**Namespace:** `langfuse`

LangFuse provides LLM-specific observability that generic metrics tools (Prometheus) cannot:

- **Prompt/response tracing** — Full conversation history with metadata
- **Token usage tracking** — Per model, per request, cumulative
- **Latency breakdowns** — TTFT, generation time, total, per tool call
- **Cost estimation** — Based on model pricing per token
- **Evaluation scores** — Attach quality scores to traces programmatically

Deployed via Helm with a bundled PostgreSQL sub-chart. For production, replace with Amazon RDS.

The Strands Agents SDK has built-in OpenTelemetry support. Traces flow:
`Strands agent → OTel Collector → LangFuse`

**Reference:** [LangFuse Kubernetes Helm](https://langfuse.com/self-hosting/kubernetes-helm)

---

## Grafana Dashboards

Four dashboards are pre-loaded via ConfigMaps:

### 1. NVIDIA GPU — DCGM Metrics

Panels: GPU Utilization (%), GPU Memory Used (GiB), Memory Usage gauge, Temperature (°C), Power Draw (W), SM Clock (MHz), Xid Errors.

Template variables: datasource (prometheus), instance (multi-select).

### 2. AWS Neuron — Inferentia/Trainium Metrics

Panels: NeuronCore Utilization (%), Device Memory Used (GiB), Memory Usage gauge, Execution Latency (ms), Execution Errors (rate/s), vCPU Usage, Model Shared Scratchpad Memory, Instance Info table.

Template variables: datasource (prometheus), instance (multi-select).

### 3. vLLM Model Serving

Panels: TTFT P50/P90/P99, Approx TPOT avg, E2E Latency P50/P90/P99, Request Throughput (QPS), Requests Waiting/Running, Token Throughput (tok/s), Tokens Processed in Selected Range, HTTP Status Codes.

Template variables: datasource (prometheus), instance (multi-select).

#### How to explain the vLLM dashboard in Spanish

This section is intended as a short speaking guide for demos or presentations.

**TTFT (Time To First Token)**
- `Tiempo hasta el primer token`
- Measures how long the model takes to start responding after the request arrives.
- It is the best quick proxy for perceived responsiveness.
- Lower is better.

**Approx TPOT / ITL (Time Per Output Token / Inter-Token Latency)**
- `Tiempo por token de salida`
- Measures the time between one generated token and the next while the model is already streaming.
- It describes how fluid the answer feels once generation has started.
- In this repo, if the native TPOT histogram is not exposed, the panel can be derived approximately as:
  - `(E2E latency sum - TTFT sum) / generation tokens`
- That means it should be explained as an average approximation, not as a true P50/P90/P99 histogram.

**End-to-End Request Latency**
- `Latencia total de la solicitud`
- Measures total time from request arrival to completed response.
- Use this when you want to explain full user-facing latency, not only response start.

**Request Throughput (QPS)**
- `Solicitudes por segundo`
- Shows how many requests the service is handling per second.
- Useful for capacity and saturation discussions.

**Requests Waiting / Running**
- `Solicitudes en espera / en ejecución`
- `Waiting` means queued requests.
- `Running` means requests actively being served.
- If `Waiting` grows and stays high, the service is saturating.

**Token Throughput (tokens/sec)**
- `Rendimiento de tokens por segundo`
- Shows processing rate for prompt tokens and generation tokens.
- This is often more useful than QPS for LLMs because request sizes vary a lot.

**HTTP Request Status Codes**
- `Códigos de estado HTTP`
- Shows the rate of successful or failed responses.
- Use it to quickly explain whether traffic is healthy (`200`) or failing (`4xx` / `5xx`).

**Tokens Processed in Selected Range**
- `Tokens procesados en el rango seleccionado`
- `Prompt tokens` are input tokens: system prompt, user prompt, and prior context sent to the model.
- `Generation tokens` are output tokens: the text produced by the model.
- This panel is easier to explain in demos because it uses the selected Grafana time range.
- In this dashboard, the panel queries:
  - `sum(increase(vllm:prompt_tokens_total{...}[$__range]))`
  - `sum(increase(vllm:generation_tokens_total{...}[$__range]))`
- So it should be explained as total tokens processed during the visible dashboard window, not as lifetime total and not as the token count of the last request.

**Suggested speaking summary**
- `TTFT tells us how fast the model starts replying.`
- `Approx TPOT tells us how fluid the response is once it starts.`
- `End-to-end latency tells us total response time.`
- `QPS and tokens per second tell us capacity.`
- `Waiting vs running tells us whether the service is saturating.`
- `Tokens in selected range tells us workload processed in the visible time window, split into input and output tokens.`

### 4. GenAI Platform Overview

Combined view: GPU/Inferentia/ARM node counts, vLLM instances, request queue, avg GPU utilization, TTFT/TPOT aggregated, token throughput, GPU utilization by node, GPU memory by node, Karpenter node pool sizing, pending pods, recent vLLM logs (Loki).

Template variables: datasource (prometheus), loki_datasource.

---

## Terraform Structure

```
infrastructure/
├── modules/observability/           # Reusable module
│   ├── main.tf                      # kube-prometheus-stack + prometheus-adapter
│   ├── dcgm_exporter.tf             # NVIDIA DCGM + GPU alerting rules
│   ├── neuron_monitor.tf            # AWS Neuron Monitor + alerting rules
│   ├── service_monitors.tf          # ServiceMonitors/PodMonitors + LLM alerting rules
│   ├── logging.tf                   # Loki + Fluent Bit
│   ├── otel_collector.tf            # OpenTelemetry Collector
│   ├── langfuse.tf                  # LangFuse + PostgreSQL
│   ├── dashboards.tf                # Grafana dashboard ConfigMaps
│   ├── variables.tf                 # All input variables
│   ├── outputs.tf                   # Endpoints for downstream consumption
│   ├── GUARDRAILS.md                # Quality monitoring & guardrails options
│   └── dashboards/
│       ├── nvidia-gpu.json          # DCGM dashboard
│       ├── aws-neuron.json          # Neuron dashboard
│       ├── vllm-serving.json        # vLLM dashboard
│       └── genai-overview.json      # Combined overview dashboard
└── lv-3-cluster-services/
    └── observability/               # Layer instantiation
        ├── providers.tf             # S3 backend + AWS/Helm/kubectl providers
        ├── main.tf                  # Module invocation
        ├── variables.tf             # Layer variables (with defaults)
        └── outputs.tf               # Exposed endpoints
```

**Feature flags:** Every component is independently toggleable:

```hcl
install_kube_prometheus_stack = true   # Prometheus + Grafana + Alertmanager
install_prometheus_adapter    = true   # Custom metrics for HPA
install_dcgm_exporter         = true   # NVIDIA GPU metrics
install_neuron_monitor        = true   # AWS Inferentia/Trainium metrics
install_loki_stack            = true   # Loki + Fluent Bit logging
install_otel_collector        = true   # OpenTelemetry tracing
install_langfuse              = true   # LLM-specific observability
```

---

## Deployment

```bash
cd infrastructure/lv-3-cluster-services/observability
terraform init
terraform plan
terraform apply
```

**Prerequisites:** EKS cluster (lv-2), Karpenter (lv-3/karpenter), and EFS (lv-3/efs) must be deployed first.

This repo's layer defaults assume the EFS stack created the `efs-sc` StorageClass for Prometheus, Loki, and LangFuse PostgreSQL persistence. If your cluster uses a different StorageClass, override:

```bash
terraform apply \
  -var="prometheus_storage_class=<your-storage-class>" \
  -var="loki_storage_class=<your-storage-class>" \
  -var="langfuse_postgres_storage_class=<your-storage-class>"
```

**Access Grafana:**
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Open http://localhost:3000 (admin / <grafana_admin_password>)
```

**Access LangFuse:**
```bash
kubectl port-forward -n langfuse svc/langfuse 3001:3000
# Open http://localhost:3001
```

---

## Connecting vLLM to the Observability Stack

To enable tracing from vLLM to the OTel Collector, add these args/env to your vLLM deployment:

```yaml
args:
  - --otlp-traces-endpoint=http://otel-collector-opentelemetry-collector.tracing.svc.cluster.local:4317
env:
  - name: OTEL_SERVICE_NAME
    value: "vllm-gpu-qwen25"   # or vllm-neuron-tinyllama, etc.
```

Metrics scraping (via ServiceMonitor) works automatically — no vLLM configuration needed. vLLM exposes `/metrics` on port 8000 by default.

---

## References

- [Neuron Monitor User Guide](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/tools/neuron-sys-tools/neuron-monitor-user-guide.html)
- [NVIDIA DCGM Exporter](https://github.com/NVIDIA/dcgm-exporter)
- [kube-prometheus-stack Helm Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Grafana Loki](https://grafana.com/docs/loki/latest/)
- [OpenTelemetry Collector Helm Chart](https://github.com/open-telemetry/opentelemetry-helm-charts)
- [LangFuse Self-Hosting (Kubernetes)](https://langfuse.com/self-hosting/kubernetes-helm)
- [vLLM Metrics](https://docs.vllm.ai/en/latest/serving/metrics.html)
- [AWS Guidance for Scalable Model Inference on EKS](https://aws.amazon.com/solutions/guidance/scalable-model-inference-and-agentic-ai-on-amazon-eks/)
