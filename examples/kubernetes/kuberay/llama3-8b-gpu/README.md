# KubeRay — Llama 3 8B on GPU via Ray Serve + vLLM

Deploys `meta-llama/Llama-3.1-8B-Instruct` using **Ray Serve** as the serving
framework and **vLLM** as the inference engine. The `RayService` CRD manages
the full cluster lifecycle — head node, GPU workers, rolling updates, and the
Serve application — as a single Kubernetes resource.

- Model: `meta-llama/Llama-3.1-8B-Instruct`
- Hardware lane: `gpu-inference` Karpenter NodePool (workers), `graviton` (head)
- API: OpenAI-compatible on port 8000 (same as vLLM, NIM, KServe)

## How it differs from the other examples

| | manual vLLM (03) | NIM Operator | KServe | **KubeRay (this)** |
|---|---|---|---|---|
| You manage | Deployment + Service | NIMCache + NIMService | InferenceService | RayService |
| Multi-replica autoscaling | HPA (external) | NIMService replicas | KServe autoscaler | Ray Serve built-in |
| Scale-to-zero | No | No | Yes (Knative) | Yes (minReplicas: 0) |
| Distributed workers | No | No | No | **Yes** |
| Rolling update | kubectl rollout | Operator-managed | Revision-based | In-place, zero-downtime |
| Model format | Any (HF Hub) | NIM containers only | Any (S3/HF) | Any (HF Hub) |

**When to choose KubeRay:**
- You need autoscaling at the GPU-replica level (not just pod replicas)
- Model is too large for one GPU and needs tensor/pipeline parallelism across workers
- You want a unified framework for both serving and batch jobs (RayJob for fine-tuning)

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  RayService: llama3-8b-ray                                   │
│                                                              │
│  ┌─────────────────────────┐    ┌────────────────────────┐  │
│  │  Head Node (ARM/Gravi.) │    │  Worker Node (GPU)     │  │
│  │  - GCS / control store  │    │  - VLLMDeployment      │  │
│  │  - Serve controller     │───▶│  - 1 replica per GPU   │  │
│  │  - HTTP proxy :8000     │    │  - vLLM engine         │  │
│  │  ~$0.04/hr              │    │  ~$1.00/hr (g6.xlarge) │  │
│  └─────────────────────────┘    └────────────────────────┘  │
│                                          ▲                   │
│                              Karpenter provisions            │
│                              GPU node on first request       │
└──────────────────────────────────────────────────────────────┘
              │
              ▼  ClusterIP :8000 (OpenAI-compatible)
        LiteLLM Gateway  →  Strands Agent
```

The head node runs on a cheap ARM/Graviton instance 24/7.  GPU workers scale
from 0 to 4 based on incoming request queue depth — Karpenter provisions the
`g6.xlarge` nodes as Ray Serve autoscales replicas up.

## Prerequisites

### 1. KubeRay operator installed

```bash
# Installed by lv-4-inference-services Terraform
kubectl get pods -n kuberay-system
kubectl get crd | grep ray
```

### 2. Cluster access

```bash
aws eks update-kubeconfig --region us-east-1 --name <your-cluster-name>
kubectl get nodepools   # should show gpu-inference and graviton
```

### 3. (Optional) HuggingFace token for gated models

Llama 3 requires accepting the license on HuggingFace first, then:

```bash
kubectl create secret generic hf-token \
  --from-literal=token=hf_xxxx... \
  -n ai-example
```

Uncomment the `HF_TOKEN` env var in `ray-service.yaml` to use it.

## Deploy

```bash
kubectl apply -f kubernetes/examples/00-namespace.yaml
kubectl apply -k kubernetes/examples/kuberay/llama3-8b-gpu
```

Watch the cluster come up:

```bash
# RayService transitions: WaitForServeDeploymentReady → Running
kubectl get rayservice llama3-8b-ray -n ai-example -w

# Watch the head pod start first (ARM node, fast)
kubectl get pods -n ai-example -l app=llama3-8b-ray-head -w

# Then the GPU worker pod (Karpenter provisions a g6.xlarge ~2-3 min)
kubectl get pods -n ai-example -l app=llama3-8b-ray-worker -w

# Karpenter node provisioning
kubectl get nodeclaims -w
kubectl get nodes -l workload=gpu
```

Ray Dashboard (useful for debugging serve app status):

```bash
kubectl port-forward -n ai-example svc/llama3-8b-ray-head-svc 8265:8265
# Open http://localhost:8265
```

## Verify

```bash
kubectl port-forward -n ai-example svc/llama3-8b-ray-serve-svc 8000:8000
```

In another terminal:

```bash
# Health check
curl http://127.0.0.1:8000/-/healthz

# List models
curl http://127.0.0.1:8000/v1/models

# Chat completion
curl http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d @kubernetes/examples/kuberay/llama3-8b-gpu/request.chat-test.json
```

## Connect to LiteLLM gateway

Add this model entry to the LiteLLM ConfigMap:

```yaml
model_list:
  - model_name: llama-3.1-8b-ray
    litellm_params:
      model: openai/llama-3.1-8b-instruct
      api_base: http://llama3-8b-ray-serve-svc.ai-example.svc.cluster.local:8000/v1
      api_key: "none"
```

The Strands agent references `llama-3.1-8b-ray` — it never knows whether the
model runs on a single vLLM pod, NIM container, KServe predictor, or a Ray
Serve cluster.

## Autoscaling demo

Ray Serve autoscales GPU worker replicas based on request queue depth.
Each new replica triggers Karpenter to provision another `g6.xlarge` node.

```bash
# Send concurrent requests to trigger scale-up
for i in $(seq 1 50); do
  curl -s http://127.0.0.1:8000/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d @kubernetes/examples/kuberay/llama3-8b-gpu/request.chat-test.json &
done
wait

# Watch replicas scale up
kubectl get rayservice llama3-8b-ray -n ai-example -w
kubectl get nodes -l workload=gpu   # more GPU nodes provisioned
```

After traffic drops, Ray Serve scales replicas back to 1 (or 0 with
`minReplicas: 0`), and Karpenter terminates the idle GPU nodes.

## Cleanup

```bash
kubectl delete -k kubernetes/examples/kuberay/llama3-8b-gpu
# GPU nodes drain and terminate automatically via Karpenter consolidation
```
