# KServe — Llama 3.1 8B on `gpu-fixed-hi-mem`

This example mirrors the fixed A10G KServe deployment, but targets the
dedicated fixed high-memory GPU lane backed by `g7e.2xlarge`.

## Deploy

```bash
kubectl apply -f examples/kubernetes/00-namespace.yaml
kubectl apply -k examples/kubernetes/kserve/llama31-8b-gpu-fixed-hi-mem
```

## Verify

```bash
kubectl get inferenceservice -n demo-examples llama31-8b-gpu-fixed-hi-mem -w
kubectl get pods -n demo-examples -l serving.kserve.io/inferenceservice=llama31-8b-gpu-fixed-hi-mem -w
```

## Cleanup

```bash
kubectl delete -k examples/kubernetes/kserve/llama31-8b-gpu-fixed-hi-mem
```
