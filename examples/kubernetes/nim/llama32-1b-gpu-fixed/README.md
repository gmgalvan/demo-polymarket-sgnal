# NIM Operator — Llama 3.2 1B on `gpu-fixed`

This example is a smaller NIM workload for `gpu-fixed`, intended to be a better
candidate for time-slicing experiments on a single `g5.2xlarge` / A10G node.

- Model: `meta/llama-3.2-1b-instruct`
- Image: `nvcr.io/nim/meta/llama-3.2-1b-instruct:1.12.0`
- Hardware lane: `gpu-fixed`
- Goal: test whether a smaller NIM can coexist with another GPU workload after
  enabling time-slicing

## Deploy

```bash
kubectl apply -f examples/kubernetes/00-namespace.yaml
kubectl apply -k examples/kubernetes/nim/llama32-1b-gpu-fixed
```

Watch:

```bash
kubectl get pods -n demo-examples -w
kubectl get nimcache,nimservice -n demo-examples -w
```

## Verify

```bash
kubectl port-forward -n demo-examples svc/llama32-1b-instruct-fixed 8000:8000
```

Then:

```bash
curl http://127.0.0.1:8000/v1/health/ready
curl http://127.0.0.1:8000/v1/models
curl http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d @examples/kubernetes/nim/llama32-1b-gpu-fixed/request.chat-test.json
```

## Cleanup

```bash
kubectl delete -k examples/kubernetes/nim/llama32-1b-gpu-fixed
```
