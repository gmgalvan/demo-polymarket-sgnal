# 04-vllm-neuron-tinyllama-1b-inf2

Deploys TinyLlama 1.1B on Inferentia (`inf2.xlarge`) using vLLM with Neuron SDK.

- Default model: `TinyLlama/TinyLlama-1.1B-Chat-v1.0` (fits on inf2.xlarge)
- Served model name: `tinyllama-1b-neuron`
- Lane: `neuron-inference`

Important:
- `vllm/vllm-neuron:latest` is not a ready-to-use public image for this flow.
- You must build and push a custom Neuron image to ECR first.
- Deployment default is `replicas: 0` to avoid `ImagePullBackOff` before image exists.
- vLLM 0.6.0 on Neuron only supports `LlamaForCausalLM` and `MistralForCausalLM` architectures.
- inf2.xlarge (16GB) only supports models ≤2B due to Neuron compilation memory overhead. For larger models use inf2.8xlarge.
- No memory limit is set on the container — Neuron compilation needs peak RAM beyond any safe cgroup limit. The pod is the sole tenant on the inf2 node.

Reference:
- AWS blog: https://aws.amazon.com/blogs/machine-learning/deploy-meta-llama-3-1-8b-on-aws-inferentia-using-amazon-eks-and-vllm/

## Prerequisites

```bash
aws sts get-caller-identity
kubectl get nodes
kubectl get nodepools
```

You should already have the `neuron-inference` nodepool created by Karpenter stack.

## Karpenter checks

```bash
kubectl get deployment -n kube-system karpenter
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter
kubectl get nodepools
kubectl get nodeclaims
```

Notes:
- Seeing `karpenter` as `1/2` can be normal on small clusters (second replica pending due scheduling constraints).
- `nodeclaims` should show a Neuron claim when this deployment is enabled.

## 1) Build and push Neuron image (recommended: ephemeral EC2 builder)

Run from this folder:

```bash
cd kubernetes/examples/manual-model-deployment/04-vllm-neuron-tinyllama-1b-inf2
AWS_REGION=us-east-1 \
ECR_REPO=vllm-neuron \
IMAGE_TAG=latest \
VLLM_REF=v0.6.0 \
INSTANCE_TYPE=m7i.4xlarge \
VOLUME_SIZE_GB=350 \
./build-and-push-ecr-ec2.sh
```

Included files:
- `Dockerfile.neuron`
- `build-and-push-ecr-ec2.sh` (recommended)
- `build-and-push-ecr.sh` (local Docker fallback)

What `build-and-push-ecr-ec2.sh` does:
- Creates ECR repo if missing
- Launches a temporary EC2 builder with large disk
- Builds and pushes the image to ECR
- Self-terminates the builder instance after successful push
- Cleans up temporary IAM role/profile + security group

IAM permissions needed for this script:
- `ec2:*` for launching/terminating the temporary builder and SG
- `iam:*` for temporary role/profile creation and cleanup
- `ecr:*` for repository/image push
- `ssm:GetParameter` to resolve latest Amazon Linux AMI

Useful overrides:
- `SUBNET_ID=subnet-xxxx` (force subnet)
- `WAIT_TIMEOUT_MIN=240` (max wait before force terminate)
- `KEEP_BUILDER_RESOURCES=true` (debug mode; no auto cleanup)

Local fallback (uses your local Docker Desktop/WSL storage):

```bash
AWS_REGION=us-east-1 ECR_REPO=vllm-neuron IMAGE_TAG=latest VLLM_REF=v0.6.0 ./build-and-push-ecr.sh
```

Confirm the image exists in ECR:

```bash
aws ecr list-images --repository-name vllm-neuron --region us-east-1
```

## Understanding the Neuron image

The Docker image is the **inference runtime** — all the software needed to run models on Inferentia. It does NOT contain any model weights.

```
┌──────────────────────────────────────────────────────────────┐
│  <account>.dkr.ecr.<region>.amazonaws.com/vllm-neuron:latest │
├──────────────────────────────────────────────────────────────┤
│  Ubuntu 20.04                                                │ ← OS base
│  Neuron SDK 2.20 + PyTorch 2.1.2                             │ ← Drivers for Inferentia chips
│  vLLM 0.6.0 (device=neuron)                                  │ ← Inference engine (OpenAI-compatible API)
│  Ray                                                         │ ← Distributed computing (tensor parallelism)
│  Transformers 4.44.2 + Tokenizers 0.19.1                     │ ← Reads model architectures
│  Triton 3.0.0                                                │ ← Kernel compiler
├──────────────────────────────────────────────────────────────┤
│  ENTRYPOINT: python3 -m vllm.entrypoints.openai.api_server   │
│  Does NOT contain any model (weights/biases)                  │
└──────────────────────────────────────────────────────────────┘
```

### Pod startup sequence

```
1. K8s creates pod on an inf2 node (Karpenter provisions if needed)
2. Pulls Docker image from ECR (runtime only)               ~15 GB, cached after first pull
3. vLLM reads --model=TinyLlama/TinyLlama-1.1B-Chat-v1.0
4. Downloads model from HuggingFace → /models (emptyDir)    ~2 GB, re-downloaded every restart
5. Compiles model for Neuron (neuronx-cc, 2 graphs)         ~5-15 min, cached in /var/tmp/
6. Starts HTTP server on :8000 with OpenAI-compatible API
```

### Why the image and model are separate

- **The image (runtime)** changes rarely — only when upgrading vLLM or Neuron SDK.
- **The model** changes often — you can try Llama, Mistral, etc. without rebuilding the image.
- The `--model` arg in the deployment YAML controls which model is loaded at startup.
- This maps to the storage strategies described in [`01-model-storage/`](../01-model-storage/).

### GPU image vs Neuron image

| | GPU | Neuron |
|---|---|---|
| Image | `vllm/vllm-openai:latest` (public) | Custom image in ECR (this repo) |
| Why custom? | vLLM ships with CUDA built-in | Neuron SDK is not in the public image; vLLM must be compiled against it |
| Supported models | All architectures vLLM supports | Only `LlamaForCausalLM` and `MistralForCausalLM` (vLLM 0.6.0) |
| Upgrade path | Change image tag | Rebuild with newer Neuron SDK + [vllm-neuron plugin](https://github.com/vllm-project/vllm-neuron) |

## 2) Hugging Face gated access (only for gated models)

The default model (`TinyLlama/TinyLlama-1.1B-Chat-v1.0`) is NOT gated — no HF token needed.

If you switch to a gated model like `meta-llama/Llama-3.2-3B-Instruct` (requires inf2.8xlarge):

1. Request/accept access on the model page (e.g. https://huggingface.co/meta-llama/Llama-3.2-3B-Instruct)
2. Create a Hugging Face token with `Read` scope.
3. Verify your token can access model files (must return `200`).

Validate token:

```bash
export HF_TOKEN='<HF_TOKEN>'
curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Authorization: Bearer ${HF_TOKEN}" \
  https://huggingface.co/meta-llama/Llama-3.2-3B-Instruct/resolve/main/config.json
```

Response meaning:
- `200`: token + model access OK
- `401`: bad token format/token invalid
- `403`: token is valid but account is not approved for this gated model

Create/update Kubernetes secret (recommended from local `.env`):

```bash
cd /home/gmgalvan/demo-polymarket-signal
HF_TOKEN=$(grep '^HUGGINGFACE_API_KEY=' .env | cut -d= -f2- | sed 's/^"//' | sed 's/"$//')

kubectl create secret generic huggingface-token \
  --from-literal=token="${HF_TOKEN}" \
  -n ai-example \
  --dry-run=client -o yaml | kubectl apply -f -
```

If your approval is still pending, keep deployment paused:

```bash
kubectl scale deployment/vllm-neuron-tinyllama-1b --replicas=0 -n ai-example
```

## 3) Deploy and enable the workload

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export IMAGE_URI=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/vllm-neuron:latest

kubectl apply -f kubernetes/examples/00-namespace.yaml
kubectl apply -k kubernetes/examples/manual-model-deployment/04-vllm-neuron-tinyllama-1b-inf2
kubectl set image deployment/vllm-neuron-tinyllama-1b vllm-neuron="${IMAGE_URI}" -n ai-example
kubectl scale deployment/vllm-neuron-tinyllama-1b --replicas=1 -n ai-example
kubectl rollout status deployment/vllm-neuron-tinyllama-1b -n ai-example
```

## 4) Verify

```bash
kubectl get nodeclaims -w
kubectl get pods -n ai-example -w
kubectl logs -n ai-example deploy/vllm-neuron-tinyllama-1b -f
```

Port-forward:

```bash
kubectl port-forward -n ai-example svc/vllm-neuron-tinyllama-1b 8000:8000
```

In another terminal:

```bash
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d @kubernetes/examples/manual-model-deployment/04-vllm-neuron-tinyllama-1b-inf2/request.chat-test.json
```

## 5) Generate demo load

Instead of backgrounding multiple `curl` commands, use the included async load script:

```bash
cd /home/gmgalvan/demo-polymarket-sgnal/kubernetes/examples/manual-model-deployment/04-vllm-neuron-tinyllama-1b-inf2
python3 load_test_async.py --requests 10 --concurrency 5
```

Useful variants:

```bash
# Gentle burst for a live demo
python3 load_test_async.py --requests 10 --concurrency 5 --print-samples 2

# Stronger burst to show queue/throughput movement
python3 load_test_async.py --requests 30 --concurrency 10

# Target a different forwarded endpoint
python3 load_test_async.py --url http://127.0.0.1:8000/v1/chat/completions --requests 20 --concurrency 8
```

What the script reports:
- total requests
- success/failure count
- wall time
- effective requests/sec
- latency min / avg / p50 / p90 / p99 / max

Recommended live-demo flow:
- Keep Grafana open on `vLLM Model Serving` and `AWS Neuron — Inferentia/Trainium Metrics`
- Run `python3 load_test_async.py --requests 10 --concurrency 5`
- Watch:
  - `Request Throughput (QPS)`
  - `Token Throughput (tokens/sec)`
  - `Requests Waiting / Running`
  - `NeuronCore Utilization (%)`
  - `End-to-End Request Latency`

## Troubleshooting

If pod is `ImagePullBackOff`:

```bash
aws ecr list-images --repository-name vllm-neuron --region us-east-1
kubectl describe pod -n ai-example -l app=vllm-neuron-tinyllama-1b
```

If pod is `CrashLoopBackOff` with:

`ImportError: cannot import name 'default_cache_dir' from triton.runtime.cache`

then rebuild and push image with this repo's updated `Dockerfile.neuron` (pins `triton==3.0.0`), then redeploy:

```bash
kubectl scale deployment/vllm-neuron-tinyllama-1b --replicas=0 -n ai-example

cd kubernetes/examples/manual-model-deployment/04-vllm-neuron-tinyllama-1b-inf2
AWS_REGION=us-east-1 ECR_REPO=vllm-neuron IMAGE_TAG=latest VLLM_REF=v0.6.0 ./build-and-push-ecr-ec2.sh

kubectl apply -k kubernetes/examples/manual-model-deployment/04-vllm-neuron-tinyllama-1b-inf2
kubectl scale deployment/vllm-neuron-tinyllama-1b --replicas=1 -n ai-example
kubectl rollout status deployment/vllm-neuron-tinyllama-1b -n ai-example
```

If pod is `CrashLoopBackOff` with `401`/`403` against Hugging Face:

```bash
kubectl logs -n ai-example deploy/vllm-neuron-tinyllama-1b --previous --tail=200
```

Fix path:

1. `401 Unauthorized`
   - token malformed (often saved with quotes) or invalid token
   - recreate `huggingface-token` secret stripping quotes from `.env`
2. `403 Forbidden`
   - token valid, but account not approved for `meta-llama/Llama-3.2-3B-Instruct`
   - wait for access approval and retry

After fixing access:

```bash
kubectl rollout restart deployment/vllm-neuron-tinyllama-1b -n ai-example
kubectl rollout status deployment/vllm-neuron-tinyllama-1b -n ai-example
```

If pod is `CrashLoopBackOff` with:

`AttributeError: TokenizersBackend has no attribute all_special_tokens_extended`

rebuild image with this repo's `Dockerfile.neuron` (pins compatible libs:
`transformers==4.44.2`, `tokenizers==0.19.1`) and redeploy:

```bash
kubectl scale deployment/vllm-neuron-tinyllama-1b --replicas=0 -n ai-example

cd kubernetes/examples/manual-model-deployment/04-vllm-neuron-tinyllama-1b-inf2
AWS_REGION=us-east-1 ECR_REPO=vllm-neuron IMAGE_TAG=latest VLLM_REF=v0.6.0 ./build-and-push-ecr-ec2.sh

kubectl apply -k kubernetes/examples/manual-model-deployment/04-vllm-neuron-tinyllama-1b-inf2
kubectl scale deployment/vllm-neuron-tinyllama-1b --replicas=1 -n ai-example
kubectl rollout status deployment/vllm-neuron-tinyllama-1b -n ai-example
```

If pod restarts with `OOMKilled` (`exitCode: 137`) while loading model shards:

```bash
kubectl get pod -n ai-example -l app=vllm-neuron-tinyllama-1b \
  -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated.reason}{" "}{.items[0].status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}'
```

Neuron compilation temporarily uses 10-12GB of RAM on top of model weights.
On inf2.xlarge (16GB), do NOT set `resources.limits.memory` — let the pod use all node RAM.
Only models ≤2B (TinyLlama, Llama-3.2-1B) fit on inf2.xlarge. For 3B+ models, use inf2.8xlarge (requires Service Quota increase to 32 vCPUs for "Running On-Demand Inf instances").

Then roll deployment:

```bash
kubectl apply -k kubernetes/examples/manual-model-deployment/04-vllm-neuron-tinyllama-1b-inf2
kubectl rollout restart deployment/vllm-neuron-tinyllama-1b -n ai-example
kubectl rollout status deployment/vllm-neuron-tinyllama-1b -n ai-example --timeout=45m
```

If pod crashes with `ValueError: Model architectures ['...'] are not supported on Neuron`:

vLLM 0.6.0 on Neuron only supports `LlamaForCausalLM` and `MistralForCausalLM`.
To support Qwen or other architectures, rebuild the image with vLLM 0.13+ and the
[vllm-neuron plugin](https://github.com/vllm-project/vllm-neuron) (requires Neuron SDK 2.28+).

If `aws ecr list-images` returns `[]`, the image was not pushed yet. Re-run build/push after checking Docker disk usage:

```bash
docker system df
df -h
```

For EC2 builder flow, also check:

```bash
aws ec2 describe-instances --filters Name=tag:ManagedBy,Values=build-and-push-ecr-ec2.sh --region us-east-1
```

If pod is `Pending`:

```bash
kubectl describe pod -n ai-example -l app=vllm-neuron-tinyllama-1b
kubectl get nodeclaims
```

## Cleanup

```bash
kubectl scale deployment -n ai-example vllm-neuron-tinyllama-1b --replicas=0
kubectl delete -k kubernetes/examples/manual-model-deployment/04-vllm-neuron-tinyllama-1b-inf2
kubectl delete secret huggingface-token -n ai-example --ignore-not-found
```

Note:
- This cleanup does not delete namespace `ai-example` anymore (shared namespace).
