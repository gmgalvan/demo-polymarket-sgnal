# ex-vllm-qwen25-3b-gpu

This sample deploys `Qwen/Qwen2.5-3B-Instruct` on the GPU lane with `vLLM` and exposes an OpenAI-compatible endpoint.

## Deploys

- Namespace: `ai-example`
- Deployment: `vllm-gpu-qwen25`
- Service: `vllm-gpu-qwen25`
- Served model name: `qwen25-3b-gpu`

## Apply

```bash
kubectl apply -k kubernetes/ex-vllm-qwen25-3b-gpu
kubectl get nodeclaims -w
kubectl get pods -n ai-example -w
kubectl rollout status deployment/vllm-gpu-qwen25 -n ai-example
```

## Karpenter checks

```bash
kubectl get deployment -n kube-system karpenter
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter
kubectl get nodepools
kubectl get nodeclaims
```

Notes:
- Seeing `karpenter` as `1/2` can be normal on small clusters (second replica pending due scheduling constraints).
- `nodeclaims` should show the GPU node claim when this example is active.

## Test

```bash
kubectl port-forward -n ai-example svc/vllm-gpu-qwen25 8000:8000
```

In another terminal:

```bash
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d @kubernetes/ex-vllm-qwen25-3b-gpu/request.chat-test.json
```

## Cleanup

```bash
kubectl delete -k kubernetes/ex-vllm-qwen25-3b-gpu
```
