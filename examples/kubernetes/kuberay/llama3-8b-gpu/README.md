# KubeRay — Llama 3.1 8B on GPU via Ray Serve LLM

Deploys `meta-llama/Llama-3.1-8B-Instruct` using the current **Ray Serve LLM**
pattern on **KubeRay**.

- Model: `meta-llama/Llama-3.1-8B-Instruct`
- Hardware lane: `gpu-inference`
- API: OpenAI-compatible on port `8000`

## What changed

This example now uses the official Serve LLM entrypoint:

- `import_path: ray.serve.llm:build_openai_app`
- official image:
  - `rayproject/ray-llm:2.52.0-py311-cu128`

That avoids the older custom `serve_vllm.py` wrapper pattern and avoids a
custom ECR build for the GPU example.

## Prerequisites

### 1. KubeRay operator installed

```bash
kubectl get pods -n kuberay-system
kubectl get crd | grep ray
```

### 2. Cluster access

```bash
aws eks update-kubeconfig --region us-east-1 --name 352-demo-dev-eks
kubectl get nodepools
```

You should see at least:

- `gpu-inference`
- `arm-general`
- `neuron-inference`

### 3. Hugging Face token for gated model access

`meta-llama/Llama-3.1-8B-Instruct` is gated on Hugging Face.

If you already have the token in AWS Secrets Manager at
`352-demo/dev/inference/api-keys`, create the Kubernetes secret used by this
example:

```bash
HF_TOKEN=$(aws secretsmanager get-secret-value \
  --secret-id 352-demo/dev/inference/api-keys \
  --region us-east-1 \
  --query SecretString \
  --output text | jq -r '.huggingface_api_key')

kubectl create secret generic huggingface-token \
  --from-literal=token="${HF_TOKEN}" \
  -n demo-examples \
  --dry-run=client -o yaml | kubectl apply -f -
```

Verify:

```bash
kubectl get secret huggingface-token -n demo-examples
```

## Deploy

```bash
kubectl delete rayservice llama3-8b-ray -n demo-examples --ignore-not-found
kubectl apply -f examples/kubernetes/00-namespace.yaml
kubectl apply -k examples/kubernetes/kuberay/llama3-8b-gpu
```

Watch the deployment:

```bash
kubectl get rayservice llama3-8b-ray -n demo-examples -w
kubectl get pods -n demo-examples -w
kubectl get nodeclaims -w
```

Expected flow:

1. KubeRay creates the RayService and RayCluster
2. Karpenter provisions GPU-lane nodes
3. The Ray head starts
4. The GPU worker starts
5. The model downloads and initializes
6. `RayService` becomes healthy

## Verify

When the service is up:

```bash
kubectl port-forward -n demo-examples svc/llama3-8b-ray-serve-svc 8000:8000
```

In another terminal:

```bash
curl http://127.0.0.1:8000/v1/models
```

```bash
curl http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d @examples/kubernetes/kuberay/llama3-8b-gpu/request.chat-test.json
```

## Notes

- This example uses the official `ray-llm` image and current Ray Serve LLM
  pattern instead of the older custom wrapper approach.
- This example was validated end-to-end on the current cluster using:
  - `rayproject/ray-llm:2.52.0-py311-cu128`
  - `gpu-inference` nodepool
  - `huggingface-token` secret in `demo-examples`
- First startup can take a while because the image is large and the model must
  download from Hugging Face.

## Cleanup

```bash
kubectl delete rayservice llama3-8b-ray -n demo-examples --ignore-not-found
```
