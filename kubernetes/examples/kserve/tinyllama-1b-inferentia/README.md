# KServe — TinyLlama 1.1B on Inferentia2

Deploys `TinyLlama/TinyLlama-1.1B-Chat-v1.0` on an Inferentia2 node (`inf2.xlarge`)
using a KServe `InferenceService` in RawDeployment mode with a custom vLLM-Neuron container.

- Model: `TinyLlama/TinyLlama-1.1B-Chat-v1.0` (same as manual example 04)
- Served model name: `tinyllama-1b-inferentia`
- Hardware lane: `neuron-inference` (Karpenter NodePool)
- API: OpenAI-compatible on port 8080 (KServe convention)

**Contrast with manual example 04:** In `04-vllm-neuron-tinyllama-1b-inf2` you write
a raw Deployment + Service. Here KServe wraps that in an `InferenceService` CRD that
adds declarative rollout management, readiness gating, and HPA integration — using
the exact same container and Neuron scheduling.

## Prerequisites

### 1. KServe installed

```bash
# Installed by lv-4-inference-services Terraform
kubectl get pods -n kserve
kubectl get crd | grep kserve
```

### 2. Custom vLLM-Neuron image in ECR

KServe does not provide a Neuron-ready image. You must build and push the same
image used in example 04:

```bash
cd kubernetes/examples/manual-model-deployment/04-vllm-neuron-tinyllama-1b-inf2
AWS_REGION=us-east-1 \
ECR_REPO=vllm-neuron \
IMAGE_TAG=latest \
VLLM_REF=v0.6.0 \
./build-and-push-ecr-ec2.sh
```

Confirm the image exists:

```bash
aws ecr list-images --repository-name vllm-neuron --region us-east-1
```

### 3. Update the image URI in inferenceservice.yaml

```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=us-east-1
```

Replace the placeholder in `inferenceservice.yaml`:

```
image: <AWS_ACCOUNT_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com/vllm-neuron:latest
```

### 4. Cluster access

```bash
aws eks update-kubeconfig --region us-east-1 --name <your-cluster-name>
kubectl get nodepools   # should show neuron-inference
```

## Deploy

```bash
kubectl apply -f kubernetes/examples/00-namespace.yaml
kubectl apply -k kubernetes/examples/kserve/tinyllama-1b-inferentia
```

Watch the InferenceService status:

```bash
kubectl get inferenceservice -n ai-example tinyllama-1b-inferentia -w
# STATUS transitions: Unknown → False (pod starting) → True (ready)
```

KServe only routes traffic to the pod once it passes readiness — `READY: True`
means the vLLM server is fully up and model is compiled on Neuron.

Watch pod and Karpenter node:

```bash
kubectl get nodeclaims -w                                       # Karpenter provisions inf2 node
kubectl get pods -n ai-example -l serving.kserve.io/inferenceservice=tinyllama-1b-inferentia -w
kubectl logs -n ai-example -l serving.kserve.io/inferenceservice=tinyllama-1b-inferentia -f
```

Neuron compilation takes 5–15 min on first start. `startupProbe` allows up to 45 min
(`failureThreshold: 180 × periodSeconds: 15`).

## Verify

KServe creates a Service named `<inferenceservice-name>-predictor`:

```bash
kubectl get svc -n ai-example | grep tinyllama
```

Port-forward:

```bash
kubectl port-forward -n ai-example svc/tinyllama-1b-inferentia-predictor 8080:80
```

In another terminal:

```bash
curl http://127.0.0.1:8080/health

curl http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d @kubernetes/examples/kserve/tinyllama-1b-inferentia/request.chat-test.json
```

## KServe vs raw Deployment comparison

| | vLLM Deployment (example 04) | KServe InferenceService (this example) |
|---|---|---|
| Resources you write | Deployment + Service | InferenceService only |
| Traffic shifting | Manual (kubectl set image) | Built-in canary via `canaryTrafficPercent` |
| Readiness gating | No (traffic hits pod immediately) | Yes (traffic only after READY=True) |
| Autoscaling | Manual HPA | KServe HPA integration |
| Port convention | 8000 (vLLM default) | 8080 (KServe convention, named `http1`) |
| Container | Same vLLM-Neuron ECR image | Same vLLM-Neuron ECR image |
| Neuron scheduling | nodeSelector + toleration in Deployment | nodeSelector + toleration in predictor spec |

## Notes on port 8080

KServe in RawDeployment mode requires the container to listen on port `8080` with
the port named `http1`. This is different from the raw vLLM Deployment in example 04
which uses `8000`. The `--port=8080` arg is passed to vLLM to match this convention.

## Cleanup

```bash
kubectl delete -k kubernetes/examples/kserve/tinyllama-1b-inferentia
kubectl delete secret huggingface-token -n ai-example --ignore-not-found
```

Karpenter will terminate the inf2 node after `consolidateAfter: 10m` with no pods scheduled.
