# NIM Operator — Llama 3.1 8B on GPU

Deploys `meta/llama-3.1-8b-instruct` on a GPU node using the NVIDIA NIM
Operator. The operator manages the full lifecycle: model download,
TensorRT-LLM optimization, pod deployment, and service exposure.

- Model: `meta/llama-3.1-8b-instruct` (NIM container from NGC)
- Served model name: `meta/llama-3.1-8b-instruct`
- Hardware lane: `gpu-nim` (dedicated Karpenter NodePool)
- API: OpenAI-compatible on port 8000

**Contrast with manual example 03:** In `03-vllm-qwen25-3b-gpu` you manage the
Deployment and Service yourself. Here the NIM Operator handles all of that — you
only write `NIMCache` (download model once) and `NIMService` (run it).

## Prerequisites

### 1. NIM Operator installed

```bash
# Installed by lv-4-inference-services Terraform
kubectl get pods -n nim-operator
kubectl get crd | grep nvidia
```

### 2. NGC API key secret

If you installed the NIM Operator through this repo's Terraform stack, it
already creates the Kubernetes secrets in `demo-examples`. Create them
manually only if you are testing the manifests without that stack.

```bash
kubectl create secret generic ngc-api-secret \
  --from-literal=NGC_API_KEY=nvapi-xxxx... \
  -n demo-examples \
  --dry-run=client -o yaml | kubectl apply -f -
```

Get the key at https://ngc.nvidia.com → Account → Setup → Generate Personal Key
(scope: `NGC Catalog`).

### 3. Cluster access

```bash
aws eks update-kubeconfig --region us-east-1 --name <your-cluster-name>
kubectl get nodepools   # should show gpu and gpu-nim
```

## How it works

```
NIMCache  →  Operator launches init job  →  pulls model from nvcr.io  →  writes to PVC
NIMService →  Operator creates Deployment →  mounts PVC (no re-download) →  serves on :8000
```

The `NIMCache` runs once. If the pod restarts, model weights are already on the PVC —
startup goes from ~20 min (fresh download) to ~2 min (load from disk).

This example uses a dedicated EFS storage class for NIM:

- `efs-sc-nim`
- `uid=1000`
- `gid=2000`
- `directoryPerms=770`

That is intentional. The NIM runtime needs read, write, and search permissions on
`/model-store`; a generic read-only cache mount did not work for this image.

The service is also pinned to a specific low-memory profile and reduced max context
length so it fits on a single `g5.2xlarge` / `A10G` node:

- profile: `a28963301b18077db3454d5eb21f5678304936c5a425ddc552443de1f5449f2a`
- `NIM_MAX_MODEL_LEN=32768`

## Deploy

```bash
kubectl apply -f examples/kubernetes/00-namespace.yaml

# Apply NIMCache first — wait for it to be Ready before NIMService starts
kubectl apply -k examples/kubernetes/nim/llama31-8b-gpu
```

Watch the cache download progress:

```bash
kubectl get nimcache -n demo-examples -w
kubectl get pods -n demo-examples -w
```

Once `NIMCache` is Ready, the `NIMService` pod starts automatically:

```bash
kubectl get nimservice -n demo-examples
kubectl get pods -n demo-examples -l app=llama31-8b-instruct -w
```

You can also confirm the PVC uses the NIM-specific storage class:

```bash
kubectl get pvc -n demo-examples llama31-8b-instruct-cache-pvc
```

## Verify

```bash
kubectl port-forward -n demo-examples svc/llama31-8b-instruct 8000:8000
```

In another terminal:

```bash
curl http://127.0.0.1:8000/v1/health/ready

curl http://127.0.0.1:8000/v1/models

curl http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d @examples/kubernetes/nim/llama31-8b-gpu/request.chat-test.json
```

## Karpenter node provisioning

When the `NIMService` pod is created with `nvidia.com/gpu: "1"`, Karpenter
automatically provisions a GPU node if none is available:

```bash
kubectl get nodeclaims -w
kubectl get nodes -l workload=gpu-nim
```

Expected instance: one of the larger single-GPU types allowed in the
`gpu-nim` lane, as configured by `gpu_nim_instance_types` in Terraform.

## Cleanup

```bash
kubectl delete -k examples/kubernetes/nim/llama31-8b-gpu
```

The NIM operator manages the PVC lifecycle for this example. The Kubernetes
secrets are created by Terraform in `lv-4-inference-services/nim-operator`, so
you usually should not delete them during normal cleanup.

## NIM vs vLLM comparison

| | vLLM (manual, example 03) | NIM Operator (this example) |
|---|---|---|
| You manage | Deployment, Service, probes | Only NIMCache + NIMService |
| Model download | Every pod restart | Once, cached on PVC |
| Optimization | vLLM default (pytorch) | NVIDIA NIM runtime with pinned low-memory vLLM profile |
| Image | Public `vllm/vllm-openai` | NVIDIA NGC `nvcr.io/nim/...` |
| NGC key needed | No | Yes |
| Canary rollout | Manual | Built-in via NIMService spec |
