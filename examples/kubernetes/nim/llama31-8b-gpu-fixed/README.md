# NIM Operator — Llama 3.1 8B on `gpu-fixed`

This example is the fixed-node variant of the NIM deployment.

- Model: `meta/llama-3.1-8b-instruct`
- Served model name: `meta/llama-3.1-8b-instruct`
- Hardware lane: `gpu-fixed`
- Node type intent: one always-on GPU node for shared experiments

Unlike the `gpu-nim` example, this one is meant to land on a dedicated fixed GPU
managed node group instead of scale-from-zero Karpenter GPU capacity.

## Prerequisites

- NIM Operator installed
- `ngc-api-secret` and `ngc-secret` already created in `demo-examples`
- `gpu-fixed` managed node group applied from Terraform
- NVIDIA device plugin and DCGM exporter updated to include `workload=gpu-fixed`

## Deploy

```bash
kubectl apply -f examples/kubernetes/00-namespace.yaml
kubectl apply -k examples/kubernetes/nim/llama31-8b-gpu-fixed
```

Watch:

```bash
kubectl get pods -n demo-examples -w
kubectl get nimcache,nimservice -n demo-examples -w
kubectl get nodes -l workload=gpu-fixed
```

## Verify

```bash
kubectl port-forward -n demo-examples svc/llama31-8b-instruct-fixed 8000:8000
```

Then:

```bash
curl http://127.0.0.1:8000/v1/health/ready
curl http://127.0.0.1:8000/v1/models
curl http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d @examples/kubernetes/nim/llama31-8b-gpu-fixed/request.chat-test.json
```

## Cleanup

```bash
kubectl delete -k examples/kubernetes/nim/llama31-8b-gpu-fixed
```
