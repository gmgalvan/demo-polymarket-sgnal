# manual-model-deployment

Manual Kubernetes deployments for validating each hardware lane independently.

These examples are applied **one at a time** with `kubectl` — they are not part of an automated pipeline. The goal is to verify that each accelerator lane (Inferentia, GPU) works correctly before wiring the full agent stack.

## Order of deployment for the talk demo

| Step | Folder | Purpose | Hardware |
|------|--------|---------|----------|
| 1 | [02-inferentia-smoke-inf2/](02-inferentia-smoke-inf2/) | Validate Inferentia lane is wired (no LLM) | inf2 node |
| 2 | [03-vllm-qwen25-3b-gpu/](03-vllm-qwen25-3b-gpu/) | Deploy vLLM + Qwen2.5-3B on GPU lane | GPU node |
| 3 | [04-vllm-neuron-tinyllama-1b-inf2/](04-vllm-neuron-tinyllama-1b-inf2/) | Deploy vLLM + TinyLlama on Inferentia lane | inf2 node |

All examples share the `ai-example` namespace. Apply it once before any example:

```bash
kubectl apply -f kubernetes/examples/00-namespace.yaml
```

## What each example proves

**02 — Inferentia smoke test**
No model, no LLM. Just confirms that:
- Karpenter can provision an `inf2` node
- The Neuron device plugin is running and advertising `aws.amazon.com/neuroncore`
- A pod that requests a neuroncore gets scheduled and responds on HTTP

Run this first before attempting any Neuron model deployment.

**03 — vLLM on GPU (Qwen2.5-3B)**
Deploys a real LLM on the GPU lane. Uses the public `vllm/vllm-openai:latest` image — no custom build required. Confirms the GPU nodepool works and the OpenAI-compatible endpoint is reachable.

**04 — vLLM on Inferentia (TinyLlama 1.1B)**
Deploys a real LLM on the Inferentia lane. Requires building a custom Neuron image (see folder README). After this example works, both accelerator lanes are validated and the agent stack can be deployed pointing to LiteLLM gateway in front of both.

## Cleanup

Scale down or delete each example individually. The namespace is shared and is not deleted by example cleanup.

```bash
# GPU example
kubectl delete -k kubernetes/examples/manual-model-deployment/03-vllm-qwen25-3b-gpu

# Inferentia smoke
kubectl delete -k kubernetes/examples/manual-model-deployment/02-inferentia-smoke-inf2

# Inferentia LLM
kubectl scale deployment -n ai-example vllm-neuron-tinyllama-1b --replicas=0
kubectl delete -k kubernetes/examples/manual-model-deployment/04-vllm-neuron-tinyllama-1b-inf2
```
