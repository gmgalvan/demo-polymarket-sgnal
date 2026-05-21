# NIM Operator — Llama 3.2 1B on `gpu-fixed-hi-mem`

This example mirrors the fixed A10G 1B NIM deployment, but targets the
dedicated fixed high-memory GPU lane backed by `g7e.2xlarge`.

## Deploy

If `lv-2-core-compute/eks` was just recreated, refresh kubeconfig first:

```bash
aws eks update-kubeconfig --region us-east-1 --name 352-demo-dev-eks
kubectl get nodes -L workload,accelerator
```

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
