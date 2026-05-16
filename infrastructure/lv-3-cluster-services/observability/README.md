# lv-3 — Platform Observability

`observability` now holds the platform telemetry stacks only. Each pillar has
its own state, providers, and lifecycle.

## Layout

| Stack | Path | Purpose |
|---|---|---|
| `monitoring` | `infrastructure/lv-3-cluster-services/observability/monitoring/` | Prometheus, Grafana, Alertmanager, prometheus-adapter, dashboards, monitors |
| `logging` | `infrastructure/lv-3-cluster-services/observability/logging/` | Loki + Fluent Bit |
| `tracing` | `infrastructure/lv-3-cluster-services/observability/tracing/` | OpenTelemetry Collector |
| `gpu-metrics` | `infrastructure/lv-3-cluster-services/observability/gpu-metrics/` | NVIDIA DCGM exporter + GPU alerts/dashboard |
| `neuron-monitor` | `infrastructure/lv-3-cluster-services/observability/neuron-monitor/` | AWS Neuron monitor + alerts/dashboard |

## Recommended Order

1. `monitoring`
2. `logging`
3. `gpu-metrics`
4. `neuron-monitor`

## Notes

- `monitoring` should come first because the other stacks assume the
  `monitoring` namespace and Prometheus/Grafana conventions already exist.
- `logging` may use a persistent storage class. In this repo the defaults assume
  `efs-sc` exists from `lv-3/efs`.
- `tracing` can export to LangFuse, which now lives in `lv-5-app-observability`.
- App-facing LLM observability is intentionally outside this folder so platform
  telemetry and application observability stay separate.
- If you previously applied the old single-stack `observability`, moving to
  this layout requires state migration or re-creation because each component
  now has its own remote state key.
