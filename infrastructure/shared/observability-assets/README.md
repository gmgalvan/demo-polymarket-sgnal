# Observability Assets

This directory holds shared observability assets that are referenced directly by
Terraform stacks but are not themselves a Terraform module.

## Contents

- `dashboards/`
  Grafana dashboard JSON files used by platform observability stacks.

- `GUARDRAILS.md`
  Notes and conventions for observability signals, dashboards, and metrics.

## Why This Exists

The previous `infrastructure/modules/observability/` directory looked like a
Terraform module, but it was not consumed as one. The active Terraform stacks
in `lv-3-cluster-services/platform-observability/` only needed shared assets
from that location, mainly dashboard JSON files.

This directory makes that intent explicit.
