# 02-inferentia-smoke-inf2

This sample validates Inferentia scheduling and Neuron resource wiring on EKS.

It does not run an LLM. It verifies that:

- `NodePool` `neuron-inference` can launch an `inf2` node
- Neuron device plugin publishes `aws.amazon.com/neuroncore`
- A pod requesting neuroncore is scheduled and serves HTTP

## Deploy

```bash
kubectl apply -f kubernetes/examples/00-namespace.yaml
kubectl apply -k kubernetes/examples/manual-model-deployment/02-inferentia-smoke-inf2
kubectl get nodeclaims -w
kubectl get pods -n ai-example -w
kubectl rollout status deployment/neuron-smoke-inf2 -n ai-example
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
- `nodeclaims` should show a Neuron claim (`neuron-inference-*`) when this example is active.

## Test

```bash
kubectl port-forward -n ai-example svc/neuron-smoke-inf2 5678:5678
```

In another terminal:

```bash
curl http://127.0.0.1:5678/
```

Expected response:

```text
Inferentia lane is healthy
```

## Verify node placement

```bash
kubectl get pods -n ai-example -o wide
kubectl describe pod -n ai-example -l app=neuron-smoke-inf2
```

You should see:

- pod on a node from `neuron-inference`
- resource request/limit: `aws.amazon.com/neuroncore: 1`

## Cleanup

```bash
kubectl delete -k kubernetes/examples/manual-model-deployment/02-inferentia-smoke-inf2
```

Note:
- This cleanup does not delete namespace `ai-example` anymore (shared namespace).
