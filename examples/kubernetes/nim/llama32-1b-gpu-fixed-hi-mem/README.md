# NIM Operator — Llama 3.2 1B on `gpu-fixed-hi-mem`

This example mirrors the fixed A10G 1B NIM deployment, but targets the
dedicated fixed high-memory GPU lane backed by `g7e.2xlarge`.

## Deploy

```bash
kubectl apply -f examples/kubernetes/00-namespace.yaml
kubectl apply -k examples/kubernetes/nim/llama32-1b-gpu-fixed-hi-mem
```

## Verify

```bash
kubectl get nimcache,nimservice -n demo-examples -w
kubectl get pods -n demo-examples -w
```

## Cleanup

```bash
kubectl delete -k examples/kubernetes/nim/llama32-1b-gpu-fixed-hi-mem
```
