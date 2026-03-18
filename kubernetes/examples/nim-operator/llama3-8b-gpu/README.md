# NIM Operator — Llama 3 8B on GPU

Deploys `meta/llama3-8b-instruct` on a GPU node (`g6.xlarge` / L40S) using the
NVIDIA NIM Operator. The operator manages the full lifecycle: model download,
TensorRT-LLM optimization, pod deployment, and service exposure.

- Model: `meta/llama3-8b-instruct` (NIM container from NGC)
- Served model name: `meta/llama3-8b-instruct`
- Hardware lane: `gpu-inference` (Karpenter NodePool)
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

```bash
kubectl create secret generic ngc-api-secret \
  --from-literal=NGC_API_KEY=nvapi-xxxx... \
  -n ai-example \
  --dry-run=client -o yaml | kubectl apply -f -
```

Get the key at https://ngc.nvidia.com → Account → Setup → Generate Personal Key
(scope: `NGC Catalog`).

### 3. Cluster access

```bash
aws eks update-kubeconfig --region us-east-1 --name 352-demo-dev-eks
kubectl get nodepools   # should show gpu-inference
```

## How it works

```
NIMCache  →  Operator launches init job  →  pulls model from nvcr.io  →  writes to PVC
NIMService →  Operator creates Deployment →  mounts PVC (no re-download) →  serves on :8000
```

The `NIMCache` runs once. If the pod restarts, model weights are already on the PVC —
startup goes from ~20 min (fresh download) to ~2 min (load from disk).

## Deploy

```bash
kubectl apply -f kubernetes/examples/00-namespace.yaml

# Apply NIMCache first — wait for it to be Ready before NIMService starts
kubectl apply -k kubernetes/examples/nim-operator/llama3-8b-gpu
```

Watch the cache download progress:

```bash
kubectl get nimcache -n ai-example -w
# STATUS transitions: Initializing → Downloading → Ready
kubectl logs -n ai-example -l nim-cache=llama3-8b-instruct-cache -f
```

Once `NIMCache` is Ready, the `NIMService` pod starts automatically:

```bash
kubectl get nimservice -n ai-example
kubectl get pods -n ai-example -l app=llama3-8b-instruct -w
```

## Verify

```bash
kubectl port-forward -n ai-example svc/llama3-8b-instruct 8000:8000
```

In another terminal:

```bash
curl http://127.0.0.1:8000/v1/health/ready

curl http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d @kubernetes/examples/nim-operator/llama3-8b-gpu/request.chat-test.json
```

List available models:

```bash
curl http://127.0.0.1:8000/v1/models
```

## Karpenter node provisioning

When the `NIMService` pod is created with `nvidia.com/gpu: "1"`, Karpenter
automatically provisions a GPU node if none is available:

```bash
kubectl get nodeclaims -w
kubectl get nodes -l workload=gpu
```

Expected instance: `g6.xlarge` (1x L40S, 24 GB VRAM) or as configured in
`var.l40s_instance_type` in lv-3 Terraform.

## Cleanup

```bash
kubectl delete -k kubernetes/examples/nim-operator/llama3-8b-gpu
kubectl delete secret ngc-api-secret -n ai-example --ignore-not-found
```

The PVC created by `NIMCache` is deleted automatically when the NIMCache resource
is deleted (operator manages the PVC lifecycle).

## NIM vs vLLM comparison

| | vLLM (manual, example 03) | NIM Operator (this example) |
|---|---|---|
| You manage | Deployment, Service, probes | Only NIMCache + NIMService |
| Model download | Every pod restart | Once, cached on PVC |
| Optimization | vLLM default (pytorch) | TensorRT-LLM (faster) |
| Image | Public `vllm/vllm-openai` | NVIDIA NGC `nvcr.io/nim/...` |
| NGC key needed | No | Yes |
| Canary rollout | Manual | Built-in via NIMService spec |
