# KubeRay — TinyLlama 1B on Inferentia2 via Ray Serve + vLLM-Neuron

Deploys `TinyLlama/TinyLlama-1.1B-Chat-v1.0` using **Ray Serve** on
**AWS Inferentia2** (`inf2.xlarge`). Workers run the custom vLLM-Neuron image
(same base as examples 04 and kserve/tinyllama-1b-inferentia) with Ray pinned
to match the RayService spec.

- Model: `TinyLlama/TinyLlama-1.1B-Chat-v1.0`
- Hardware lane: `neuron-inference` Karpenter NodePool (workers), `graviton` (head)
- API: OpenAI-compatible on port 8000

## Key differences vs the GPU RayService example

| | GPU (llama3-8b-gpu) | **Inferentia (this)** |
|---|---|---|
| Worker image | Public `rayproject/ray-ml:2.32.0-gpu` | Custom ECR `vllm-neuron-ray:2.32.0` |
| Accelerator resource | `nvidia.com/gpu: 1` | `aws.amazon.com/neuroncore: 1` |
| Max model length | 4096 tokens | **512 tokens** (fixed XLA graph) |
| First-start time | ~5 min (model download) | **20-45 min** (Neuron XLA compilation) |
| Scale-to-zero | Yes (`minReplicas: 0`) | **No** (`minReplicas: 1`) — recompile cost |
| Max replicas | 4 (one GPU each) | 2 (inf2.xlarge has 2 NeuronCores) |
| Cost vs GPU | ~$1.00/hr (g6.xlarge) | **~$0.23/hr** (inf2.xlarge, ~77% cheaper) |

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  RayService: tinyllama-neuron-ray                                │
│                                                                  │
│  ┌─────────────────────────┐    ┌──────────────────────────────┐ │
│  │  Head Node (ARM/Gravi.) │    │  Worker Node (Inferentia2)   │ │
│  │  - GCS / control store  │    │  - VLLMNeuronDeployment      │ │
│  │  - Serve controller     │───▶│  - 1 replica per NeuronCore  │ │
│  │  - HTTP proxy :8000     │    │  - vLLM (device=neuron)      │ │
│  │  ~$0.04/hr              │    │  ~$0.23/hr (inf2.xlarge)     │ │
│  └─────────────────────────┘    └──────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

`inf2.xlarge` has **2 NeuronCores**.  With `tensor_parallel_size=1`, each
replica uses 1 NeuronCore → you can run up to 2 replicas on a single node.

## Prerequisites

### 1. Build and push the Ray-Neuron worker image

The worker needs both the Neuron SDK and Ray 2.32.0 pinned together.

```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=us-east-1
export BASE_IMAGE=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/vllm-neuron:latest

# Authenticate to ECR
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Create the repo if it doesn't exist
aws ecr create-repository --repository-name vllm-neuron-ray --region ${AWS_REGION} || true

# Build (must run on x86_64 — Neuron SDK does not have an ARM build)
docker build \
  --build-arg VLLM_NEURON_URI=${BASE_IMAGE} \
  -t ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/vllm-neuron-ray:2.32.0 \
  -f kubernetes/examples/kuberay/tinyllama-1b-inferentia/Dockerfile.ray-neuron \
  .

docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/vllm-neuron-ray:2.32.0
```

If you have not built `vllm-neuron:latest` yet, do it first:

```bash
cd kubernetes/examples/manual-model-deployment/04-vllm-neuron-tinyllama-1b-inf2
AWS_REGION=us-east-1 ECR_REPO=vllm-neuron IMAGE_TAG=latest VLLM_REF=v0.6.0 \
  ./build-and-push-ecr-ec2.sh
```

### 2. Update the worker image URI in `ray-service.yaml`

Replace `<AWS_ACCOUNT_ID>` and `<AWS_REGION>` in the `workerGroupSpecs` container image field.

### 3. Verify KubeRay and Karpenter

```bash
kubectl get pods -n kuberay-system
kubectl get nodepools   # should show neuron-inference
```

## Deploy

```bash
kubectl apply -f kubernetes/examples/00-namespace.yaml
kubectl apply -k kubernetes/examples/kuberay/tinyllama-1b-inferentia
```

Watch the deployment:

```bash
# RayService status (takes up to 45 min on first deploy due to Neuron compilation)
kubectl get rayservice tinyllama-neuron-ray -n ai-example -w

# Head pod starts fast (ARM node)
kubectl get pods -n ai-example -l app=tinyllama-neuron-ray-head -w

# Worker pod (Karpenter provisions inf2.xlarge, then Neuron compiles the model)
kubectl get pods -n ai-example -l app=tinyllama-neuron-ray-worker -w

# Follow Neuron compilation logs
kubectl logs -n ai-example -l app=tinyllama-neuron-ray-worker -f
# Look for: "neuronx_distributed: Compiled model saved to /tmp/neuron_cache/..."
```

Karpenter node provisioning:

```bash
kubectl get nodeclaims -w
kubectl get nodes -l workload=neuron
```

## Verify

Once `RayService` status shows `Running`:

```bash
kubectl port-forward -n ai-example svc/tinyllama-neuron-ray-serve-svc 8000:8000
```

In another terminal:

```bash
curl http://127.0.0.1:8000/-/healthz

curl http://127.0.0.1:8000/v1/models

curl http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d @kubernetes/examples/kuberay/tinyllama-1b-inferentia/request.chat-test.json
```

## Connect to LiteLLM gateway

```yaml
model_list:
  - model_name: tinyllama-1b-neuron-ray
    litellm_params:
      model: openai/tinyllama-1b-neuron
      api_base: http://tinyllama-neuron-ray-serve-svc.ai-example.svc.cluster.local:8000/v1
      api_key: "none"
```

## Why `max_model_len: 512`?

Neuron XLA compiles a **static computation graph** for a fixed sequence length.
Changing `max_model_len` requires recompiling (another 20-45 min). 512 is the
minimum that fits a typical trading signal analysis prompt + response.

For longer sequences, recompile with a higher value and cache the new NEFF.
Using EFS to persist `/tmp/neuron_cache` across nodes avoids recompilation when
Karpenter replaces a node.

## Neuron cache persistence (production tip)

The default `emptyDir` cache is lost when the pod restarts on a different node.
For production, use an EFS-backed PVC:

```yaml
volumes:
  - name: neuron-cache
    persistentVolumeClaim:
      claimName: neuron-cache-efs-pvc
```

Pre-populate the cache once, then all future starts load in ~2-3 min instead
of 20-45 min.

## Cleanup

```bash
kubectl delete -k kubernetes/examples/kuberay/tinyllama-1b-inferentia
# Karpenter consolidates and terminates the inf2.xlarge node automatically
```
