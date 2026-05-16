# lv-5 — App Observability

This layer holds application-facing observability that sits above the base
cluster/platform telemetry stacks.

## Layout

| Stack | Path | Purpose |
|---|---|---|
| `langfuse` | `infrastructure/lv-5-app-observability/langfuse/` | LLM/application tracing UI, prompt history, token/cost visibility, evaluation hooks |

## Dependencies

- `lv-2-core-compute/eks`
- `lv-3-cluster-services/efs` if you use the default `efs-sc` storage class
- `lv-3-cluster-services/observability/monitoring` if you want Grafana/Prometheus already in place

## Note

If you previously applied LangFuse from the old
`lv-3-cluster-services/observability/langfuse` stack, moving to this layout
requires state migration or re-creation because the remote state key changed.
