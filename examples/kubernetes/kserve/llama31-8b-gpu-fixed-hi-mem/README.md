# KServe — Llama 3.1 8B on `gpu-fixed-hi-mem`

This example mirrors the fixed A10G KServe deployment, but targets the
dedicated fixed high-memory GPU lane backed by `g7e.2xlarge`.

## Deploy

If `lv-2-core-compute/eks` was just recreated, refresh kubeconfig first:

```bash
aws eks update-kubeconfig --region us-east-1 --name 352-demo-dev-eks
kubectl get nodes -L workload,accelerator
```

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
