# KubeRay — TinyLlama 1B on Inferentia2 via AWS blueprint pattern

This example is validated end-to-end in this repo using the AWS AI on EKS
`vllm-rayserve-inf2` pattern instead of `ray.serve.llm:build_openai_app`.

Working stack:

- Ray `2.32.0`
- AWS published image:
  - `public.ecr.aws/data-on-eks/vllm-ray2.32.0-inf2-llama3:latest`
- custom `vllm_serve.py` wrapper mounted from a `ConfigMap`
- model:
  - `TinyLlama/TinyLlama-1.1B-Chat-v1.0`
- public served model name:
  - `tinyllama-1b-neuron`

Reference:

- https://awslabs.github.io/ai-on-eks/docs/blueprints/inference/framework-guides/Neuron/vllm-ray-inf2

## What changed from AWS

The upstream blueprint targets a larger Llama model and different node labels.
This repo adapts it to:

- head on:
  - `workload: x86-core`
- worker on:
  - `workload: neuron`
- `inf2.xlarge`-sized TinyLlama settings:
  - `tensor_parallel_size=2`
  - `max_model_len=512`
  - `max_num_seqs=4`
  - `block_size=512`
- `aws.amazon.com/neuroncore: "2"` for the worker

## Prerequisites

```bash
kubectl get nodepools
kubectl get pods -n kuberay-system
```

You should have:

- `x86-core`
- `neuron-inference`

And the examples namespace:

```bash
kubectl apply -f examples/kubernetes/00-namespace.yaml
```

## Deploy

This path does **not** require building a custom image.

```bash
kubectl apply -k examples/kubernetes/kuberay/tinyllama-1b-inferentia
```

Watch the rollout:

```bash
kubectl get rayservice tinyllama-neuron-ray -n demo-examples -w
kubectl get pods -n demo-examples -w
kubectl get nodeclaims -w
```

Expected shape:

- one head pod on `x86-core`
- one running worker on `workload=neuron`

## Verify

When the RayService reports `Running`, find the current head service:

```bash
kubectl get svc -n demo-examples | grep tinyllama-neuron-ray
```

Then port-forward the current head service, for example:

```bash
kubectl port-forward -n demo-examples svc/tinyllama-neuron-ray-raycluster-<ID>-head-svc 8000:8000
```

Test the served model list:

```bash
curl http://127.0.0.1:8000/v1/models
```

Expected response includes:

- `tinyllama-1b-neuron`

Then test chat completions:

```bash
curl http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d @examples/kubernetes/kuberay/tinyllama-1b-inferentia/request.chat-test.json
```

## Notes

- The earlier `build_openai_app` path was removed because it did not match the
  Neuron vLLM stack published by AWS.
- This example now pins a single Serve replica and a single worker group
  replica to keep demos predictable on `inf2.xlarge`.

## Cleanup

```bash
kubectl delete -k examples/kubernetes/kuberay/tinyllama-1b-inferentia
```
