# lv-3 — Platform Observability

`observability` now holds the platform telemetry stacks only. Each pillar has
its own state, providers, and lifecycle.

## Layout

| Stack | Path | Purpose |
|---|---|---|
| `01-monitoring` | `infrastructure/lv-3-cluster-services/platform-observability/01-monitoring/` | Prometheus, Grafana, Alertmanager, prometheus-adapter, dashboards, monitors |
| `02-logging` | `infrastructure/lv-3-cluster-services/platform-observability/02-logging/` | Loki + Fluent Bit |
| `03-tracing` | `infrastructure/lv-3-cluster-services/platform-observability/03-tracing/` | OpenTelemetry Collector |
| `04-gpu-metrics` | `infrastructure/lv-3-cluster-services/platform-observability/04-gpu-metrics/` | NVIDIA DCGM exporter + GPU alerts/dashboard |
| `05-neuron-monitor` | `infrastructure/lv-3-cluster-services/platform-observability/05-neuron-monitor/` | AWS Neuron monitor + alerts/dashboard |

## Recommended Order

1. `01-monitoring`
2. `02-logging`
3. `03-tracing`
4. `04-gpu-metrics`
5. `05-neuron-monitor`

## Notes

- Accelerator device plugins are managed separately in
  `lv-3-cluster-services/nvidia-device-plugin` and
  `lv-3-cluster-services/neuron-device-plugin` so Karpenter can stay focused
  on node provisioning.
- `01-monitoring` should come first because the other stacks assume the
  `monitoring` namespace and Prometheus/Grafana conventions already exist.
- `01-monitoring` now reads the Grafana admin password from
  `lv-1-security-and-config/secrets`.
- `02-logging` may use a persistent storage class. In this repo the defaults assume
  `efs-sc` exists from `lv-3/efs`.
- `03-tracing` can export to LangFuse, which now lives in `lv-5-app-observability`.
- App-facing LLM observability is intentionally outside this folder so platform
  telemetry and application observability stay separate.
- If you previously applied the old single-stack `observability`, moving to
  this layout requires state migration or re-creation because each component
  now has its own remote state key.
- Renaming these split stacks to numbered directories and then to
  `platform-observability` changes their remote state keys. Run
  `terraform init -migrate-state` or re-create the stacks.
