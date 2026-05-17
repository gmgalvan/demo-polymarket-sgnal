# lv-1 — Security And Config

This layer holds shared runtime secrets and configuration that should exist
before higher-level infrastructure stacks consume them.

## Layout

| Stack | Path | Purpose |
|---|---|---|
| `secrets` | `infrastructure/lv-1-security-and-config/secrets/` | Shared Secrets Manager secrets for platform and app stacks |

## Notes

- Use this layer for shared secrets/config that should not be hardcoded in
  downstream Terraform stacks.
- Keep secrets and non-secret configs split across separate stacks as the layer
  grows. This stack is only for secrets.
- Platform stacks such as monitoring can read secret names from this layer via
  remote state and then resolve the current secret value from Secrets Manager.
- If a stack was previously using inline/default secrets, moving to this layer
  does not migrate the old values automatically. Apply this stack first, then
  update downstream stacks to read from it.
