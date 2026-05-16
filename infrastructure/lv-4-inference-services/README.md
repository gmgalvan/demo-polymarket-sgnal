# lv-4 — Inference Services

`lv-4` is now split into independent stacks so each controller has its own
state, providers, and lifecycle.

## Layout

| Stack | Path | Purpose |
|---|---|---|
| `cert-manager` | `infrastructure/lv-4-inference-services/cert-manager/` | TLS certs for KServe webhooks |
| `kserve` | `infrastructure/lv-4-inference-services/kserve/` | InferenceService CRD and serving controller |
| `kuberay` | `infrastructure/lv-4-inference-services/kuberay/` | RayCluster/RayJob/RayService controller |
| `nim-operator` | `infrastructure/lv-4-inference-services/nim-operator/` | NVIDIA NIM Operator and NGC auth secret |

## Dependencies

All stacks require:

```bash
lv-2-core-compute/eks
```

Recommended before inference workloads:

```bash
lv-3-cluster-services/karpenter
```

Required order inside `lv-4`:

1. `cert-manager`
2. `kserve`
3. `kuberay`
4. `nim-operator` (optional, requires `NGC_API_KEY`)

## Usage

```bash
cd infrastructure/lv-4-inference-services/cert-manager
terraform init
terraform apply

cd ../kserve
terraform init
terraform apply

cd ../kuberay
terraform init
terraform apply

cd ../nim-operator
terraform init
terraform apply -var="ngc_api_key=nvapi-xxxx..."
```

## Verify

```bash
kubectl get pods -n cert-manager
kubectl get pods -n kserve
kubectl get pods -n kuberay-system
kubectl get pods -n nim-operator
kubectl get crd | grep -E "kserve|ray|nim"
```

## Note

If you already had a deployed single-stack `lv-4`, moving to this layout
requires state migration or re-creation because each controller now has its own
remote state key.
