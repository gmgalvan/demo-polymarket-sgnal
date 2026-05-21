# KServe — Llama 3.1 8B on gpu-fixed

Deploys `meta-llama/Llama-3.1-8B-Instruct` through a KServe `InferenceService`
in RawDeployment mode on the fixed GPU lane.

- Model: `meta-llama/Llama-3.1-8B-Instruct`
- Served model name: `llama31-8b-gpu-fixed`
- Runtime: `vllm/vllm-openai:latest`
- Hardware lane: `gpu-fixed`
- API: OpenAI-compatible on port `8080` (KServe convention)

This example is intentionally separate from the NIM examples:

- `examples/kubernetes/nim/llama31-8b-gpu-fixed` = NIM Operator + NGC image
- `examples/kubernetes/kserve/llama31-8b-gpu-fixed` = KServe + vLLM image

## Prerequisites

### 1. KServe installed

```bash
kubectl get pods -n kserve
kubectl get crd | grep kserve
```

### 2. Hugging Face token secret

Because this uses the public vLLM image and pulls the model from Hugging Face,
you need a token secret in `demo-examples`:

```bash
kubectl create secret generic huggingface-token \
  -n demo-examples \
  --from-literal=token='<YOUR_HF_TOKEN>'
```

### 3. gpu-fixed node available

```bash
kubectl get nodes -L workload,accelerator | grep gpu-fixed
```

## Recommended cleanup first

If the NIM fixed example is still using the only fixed GPU, remove it first:

```bash
kubectl delete -k examples/kubernetes/nim/llama31-8b-gpu-fixed
```

## Deploy

```bash
kubectl apply -f examples/kubernetes/00-namespace.yaml
kubectl apply -k examples/kubernetes/kserve/llama31-8b-gpu-fixed
```

Watch the rollout:

```bash
kubectl get inferenceservice -n demo-examples llama31-8b-gpu-fixed -w
kubectl get pods -n demo-examples -l serving.kserve.io/inferenceservice=llama31-8b-gpu-fixed -w
kubectl logs -n demo-examples -l serving.kserve.io/inferenceservice=llama31-8b-gpu-fixed -f
```

## Verify

KServe creates a predictor service named:

```bash
kubectl get svc -n demo-examples | grep llama31-8b-gpu-fixed
```

Port-forward:

```bash
kubectl port-forward -n demo-examples svc/llama31-8b-gpu-fixed-predictor 8080:80
```

In another terminal:

```bash
curl http://127.0.0.1:8080/health
curl http://127.0.0.1:8080/v1/models
curl http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d @examples/kubernetes/kserve/llama31-8b-gpu-fixed/request.chat-test.json
```

## Notes

- `port 8080` and port name `http1` are required by KServe RawDeployment mode.
- `max-model-len=4096` is intentionally conservative for a single A10G.
- `emptyDir` is used for `/models`; if the pod is recreated, the model is
  downloaded again.

## Cleanup

```bash
kubectl delete -k examples/kubernetes/kserve/llama31-8b-gpu-fixed
```
