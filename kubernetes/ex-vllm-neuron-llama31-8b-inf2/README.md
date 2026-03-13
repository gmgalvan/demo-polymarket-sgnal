# ex-vllm-neuron-llama31-8b-inf2

This sample deploys Llama 3.1 8B on Inferentia (`inf2`) using vLLM.

- Model: `meta-llama/Llama-3.1-8B-Instruct`
- Served model name: `llama31-8b-neuron`
- Lane: `neuron-inference`

Important:
- `vllm/vllm-neuron:latest` is not a ready-to-use public image for this flow.
- You must build and push a custom Neuron image to ECR first.
- Deployment default is `replicas: 0` to avoid `ImagePullBackOff` before image exists.

Reference:
- AWS blog: https://aws.amazon.com/blogs/machine-learning/deploy-meta-llama-3-1-8b-on-aws-inferentia-using-amazon-eks-and-vllm/

## Prerequisites

```bash
aws sts get-caller-identity
kubectl get nodes
kubectl get nodepools
```

You should already have the `neuron-inference` nodepool created by Karpenter stack.

## Karpenter checks

```bash
kubectl get deployment -n kube-system karpenter
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter
kubectl get nodepools
kubectl get nodeclaims
```

Notes:
- Seeing `karpenter` as `1/2` can be normal on small clusters (second replica pending due scheduling constraints).
- `nodeclaims` should show a Neuron claim when this deployment is enabled.

## 1) Build and push Neuron image

Run from this folder:

```bash
cd kubernetes/ex-vllm-neuron-llama31-8b-inf2
AWS_REGION=us-east-1 ECR_REPO=vllm-neuron IMAGE_TAG=latest VLLM_REF=v0.6.0 ./build-and-push-ecr.sh
```

Included files:
- `Dockerfile.neuron`
- `build-and-push-ecr.sh`

Build notes:
- `build-and-push-ecr.sh` auto-creates the ECR repository if it does not exist.
- This build is heavy (large Neuron base image + vLLM compile path). Keep enough Docker disk space before starting.
- If your Windows `C:` drive is nearly full, Docker Desktop builds may fail or stall even when WSL `/` has free space.

Confirm the image exists in ECR:

```bash
aws ecr list-images --repository-name vllm-neuron --region us-east-1
```

## 2) Optional Hugging Face token

```bash
kubectl create secret generic huggingface-token \
  --from-literal=token='<HF_TOKEN>' \
  -n ai-example
```

## 3) Deploy and enable the workload

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export IMAGE_URI=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/vllm-neuron:latest

kubectl apply -k kubernetes/ex-vllm-neuron-llama31-8b-inf2
kubectl set image deployment/vllm-neuron-llama31-8b vllm-neuron="${IMAGE_URI}" -n ai-example
kubectl scale deployment/vllm-neuron-llama31-8b --replicas=1 -n ai-example
kubectl rollout status deployment/vllm-neuron-llama31-8b -n ai-example
```

## 4) Verify

```bash
kubectl get nodeclaims -w
kubectl get pods -n ai-example -w
kubectl logs -n ai-example deploy/vllm-neuron-llama31-8b -f
```

Port-forward:

```bash
kubectl port-forward -n ai-example svc/vllm-neuron-llama31-8b 8000:8000
```

In another terminal:

```bash
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d @kubernetes/ex-vllm-neuron-llama31-8b-inf2/request.chat-test.json
```

## Troubleshooting

If pod is `ImagePullBackOff`:

```bash
aws ecr list-images --repository-name vllm-neuron --region us-east-1
kubectl describe pod -n ai-example -l app=vllm-neuron-llama31-8b
```

If `aws ecr list-images` returns `[]`, the image was not pushed yet. Re-run build/push after checking Docker disk usage:

```bash
docker system df
df -h
```

If pod is `Pending`:

```bash
kubectl describe pod -n ai-example -l app=vllm-neuron-llama31-8b
kubectl get nodeclaims
```

If model does not fit `inf2.xlarge`, use a larger Inferentia type (for example `inf2.8xlarge`).

## Cleanup

```bash
kubectl scale deployment -n ai-example vllm-neuron-llama31-8b --replicas=0
kubectl delete -k kubernetes/ex-vllm-neuron-llama31-8b-inf2
kubectl delete secret huggingface-token -n ai-example --ignore-not-found
```
