# Model Configuration

> **Status: Draft** — Design phase. Model configuration described here has not been deployed yet.

## Overview

This document specifies which model we use, why, how it's served on each hardware backend, and the practical requirements for deployment.

---

## Model Choice: Llama 3.1 8B-Instruct

| Property | Value |
|----------|-------|
| Model | `meta-llama/Llama-3.1-8B-Instruct` |
| Parameters | 8 billion |
| Context Window | 128K tokens (we use ~4K in practice) |
| License | Llama 3.1 Community License (free for commercial use) |
| Tool Calling | Native support (required by Strands agent loop) |
| Languages | English primary, multilingual supported |

### Why This Model

**Tool calling is non-negotiable.** Strands Agents SDK uses the model's native function-calling capability to decide which tools to invoke. Models without tool-calling support cannot drive the agent loop. Llama 3.1 Instruct has robust tool-calling built in.

**8B fits on minimal hardware.** The model runs in FP16 on a single A10G (24GB VRAM) with room for KV cache. On Inferentia, 8B models require inf2.8xlarge (128GB) due to Neuron compilation memory overhead; inf2.xlarge (16GB) only supports small models like TinyLlama 1.1B or Llama 3.2 1B. This keeps demo infrastructure costs low — no multi-GPU setups needed.

**Same model on both backends proves the thesis.** The talk's core message is hardware abstraction. Using identical models on GPU and Inferentia eliminates the variable of "maybe it's a different model" — the only difference is the chip.

**Open weights, no API keys.** No external model API dependency. The model runs entirely inside the EKS cluster. One less thing that can fail during a live demo.

### Alternatives Considered

| Model | Why Not |
|-------|---------|
| Llama 3.1 70B | Requires multi-GPU (g5.12xlarge) or large Inferentia instances. Increases demo cost significantly. The 8B is sufficient for the demo's reasoning tasks. |
| Mistral 7B v0.3 | Good tool-calling support, but Neuron SDK compilation is less tested than Llama. Adds risk. |
| Qwen3-4B | Smaller and faster, but tool-calling reliability is less proven at this parameter scale. |
| Claude / GPT-4 via API | Would defeat the purpose — the demo is about running models locally on EKS, not calling external APIs. |

---

## GPU Backend: vLLM with CUDA

### Configuration

```yaml
# Simplified Kubernetes deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm-gpu
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: vllm
          image: vllm/vllm-openai:latest
          args:
            - --model=meta-llama/Llama-3.1-8B-Instruct
            - --dtype=float16
            - --max-model-len=4096
            - --gpu-memory-utilization=0.90
            - --enable-auto-tool-choice
            - --tool-call-parser=llama3_json
          ports:
            - containerPort: 8000
          resources:
            limits:
              nvidia.com/gpu: 1
            requests:
              cpu: "4"
              memory: "16Gi"
      tolerations:
        - key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule
```

### Requirements

| Resource | Value |
|----------|-------|
| Instance | g5.xlarge |
| GPU | 1x NVIDIA A10G |
| VRAM | 24 GB (model uses ~16GB FP16 + KV cache) |
| CPU | 4 vCPUs |
| RAM | 16 GB |
| Storage | 20 GB (model weights download) |
| Estimated cost | ~$1.01/hr on-demand |

### Key vLLM Flags

- `--enable-auto-tool-choice` — Required for Strands tool calling to work
- `--tool-call-parser=llama3_json` — Tells vLLM to parse Llama 3.1's native tool-calling format
- `--max-model-len=4096` — We don't need 128K context for this demo; limiting it saves VRAM for larger batches
- `--gpu-memory-utilization=0.90` — Use 90% of VRAM for model + KV cache

---

## Inferentia Backend: vLLM with Neuron SDK

### How It Works

Unlike GPU, Inferentia does NOT use pre-compiled models with `optimum-neuron`. Instead, vLLM compiles the model at pod startup using the Neuron compiler (`neuronx-cc`). This takes 5-15 minutes on first boot but the compiled NEFFs are cached in `/var/tmp/neuron-compile-cache` for subsequent restarts.

The Docker image is the **inference runtime only** — it contains vLLM, Neuron SDK, Ray, and dependencies but NO model weights. The model is downloaded from Hugging Face at startup via the `--model` arg.

### Custom Image (Required)

vLLM's public Docker image does not include the Neuron SDK. You must build and push a custom image to ECR. See `kubernetes/ex-vllm-neuron-llama32-3b-inf2/README.md` for full build instructions.

Key components in the image:
- Base: `public.ecr.aws/neuron/pytorch-inference-neuronx:2.1.2-neuronx-py310-sdk2.20.0-ubuntu20.04`
- vLLM 0.6.0 compiled with `VLLM_TARGET_DEVICE=neuron`
- Pinned dependencies: `transformers==4.44.2`, `tokenizers==0.19.1`, `triton==3.0.0`
- `pyairports` (required by `outlines`, not declared as dependency)

### Configuration

```yaml
args:
  - --model=TinyLlama/TinyLlama-1.1B-Chat-v1.0
  - --served-model-name=tinyllama-1b-neuron
  - --device=neuron
  - --tensor-parallel-size=1
  - --max-model-len=512
  - --max-num-seqs=1
  - --block-size=2048
  - --swap-space=0
  - --guided-decoding-backend=lm-format-enforcer
resources:
  requests:
    cpu: "1500m"
    memory: "10Gi"
    aws.amazon.com/neuroncore: "1"
  limits:
    cpu: "3"
    aws.amazon.com/neuroncore: "1"
    # No memory limit — Neuron compilation requires peak RAM that exceeds
    # any safe cgroup limit on inf2.xlarge. The pod is the sole tenant on
    # the node, so this is safe.
```

### inf2 Instance Sizing

| Instance | RAM | Neuron Cores | vCPUs | Max Model (bf16) | Notes |
|----------|-----|-------------|-------|------------------|-------|
| inf2.xlarge | 16 GB | 2 | 4 | ~1-2B (TinyLlama, Llama-3.2-1B) | Neuron compilation overhead limits usable RAM |
| inf2.8xlarge | 128 GB | 2 | 32 | ~8B (Llama 3.1 8B) | Requires Service Quota increase (32 vCPUs) |
| inf2.24xlarge | 384 GB | 12 | 96 | ~30B+ | Multi-core tensor parallelism |

**Important:** inf2.xlarge has 16GB total but only ~14.6GB allocatable by Kubernetes. Neuron compilation temporarily uses 10-12GB on top of model weights, which is why memory limits must NOT be set — the pod needs access to all node memory during compilation.

### Supported Architectures (vLLM 0.6.0 on Neuron)

Only two model architectures are supported:
- `LlamaForCausalLM` (Llama, TinyLlama, Code Llama)
- `MistralForCausalLM` (Mistral, Mixtral)

For Qwen or other architectures, upgrade to vLLM 0.13+ with the [vllm-neuron plugin](https://github.com/vllm-project/vllm-neuron) (requires Neuron SDK 2.28+).

### Known Issues

- **`outlines` missing `pyairports`**: vLLM bundles `outlines` for guided decoding, but `outlines` imports `pyairports` without declaring it as a dependency. Fix: install `pyairports` in the Docker image AND use `--guided-decoding-backend=lm-format-enforcer` to bypass `outlines` entirely.
- **OOMKilled on inf2.xlarge**: Even TinyLlama (2GB) gets OOMKilled if a memory limit is set, because Neuron compilation temporarily spikes to 12-14GB. Fix: do not set `resources.limits.memory`.
- **`tensor-parallel-size=2` adds Ray overhead**: Using tp=2 starts Ray distributed computing, adding ~2-3GB RAM overhead. On inf2.xlarge, always use tp=1.

### Inferentia Limitations

- **Compilation happens at startup** — First boot takes 5-15 minutes while `neuronx-cc` compiles computation graphs. Subsequent restarts use cached NEFFs.
- **Not all models work** — Only `LlamaForCausalLM` and `MistralForCausalLM` on vLLM 0.6.0.
- **inf2.xlarge is very constrained** — Only small models (≤2B) fit due to compilation memory overhead. Budget for inf2.8xlarge for production use.
- **Tool calling via vLLM** — The `--enable-auto-tool-choice` flag works the same way regardless of backend. The Neuron SDK handles the compute; vLLM handles the API layer.

---

## LiteLLM Gateway Configuration

Both backends register under the same model name in LiteLLM so the Strands agent sees a single model:

```yaml
model_list:
  - model_name: llama-3.1-8b
    litellm_params:
      model: openai/meta-llama/Llama-3.1-8B-Instruct
      api_base: http://vllm-gpu:8000/v1
    model_info:
      description: "GPU backend (A10G)"

  - model_name: llama-3.1-8b
    litellm_params:
      model: openai/meta-llama/Llama-3.1-8B-Instruct
      api_base: http://vllm-neuron:8000/v1
    model_info:
      description: "Neuron backend (inf2)"

router_settings:
  routing_strategy: least-busy
  enable_fallbacks: true
  fallbacks:
    - llama-3.1-8b:
        - llama-3.1-8b  # Same name = LiteLLM tries the other backend
```

### How Failover Works

1. Agent calls LiteLLM: `POST /v1/chat/completions` with `model: llama-3.1-8b`
2. LiteLLM routes to the least-busy backend (GPU or Neuron)
3. If that backend returns an error or times out, LiteLLM retries on the other backend
4. Agent receives response — never knows which backend served it

---

## Cost Comparison

| Backend | Instance | Hourly Cost | Notes |
|---------|----------|------------|-------|
| GPU (g6e.xlarge) | 1x L40S | ~$1.86/hr | Universal compatibility, fastest time-to-first-token |
| Inferentia (inf2.xlarge) | 1 Neuron core | ~$0.76/hr | Small models only (≤2B), compilation at startup |
| Inferentia (inf2.8xlarge) | 2 Neuron cores | ~$1.97/hr | Supports 8B models, requires Service Quota increase |
| ARM (m7g.medium) | CPU only | ~$0.04/hr | For agent, MCP servers, gateway — no inference |

Running 24/7 for a month:
- GPU only: ~$727/mo
- Inferentia only: ~$547/mo (25% savings)
- Mixed (GPU primary + Inferentia fallback): depends on routing split

For the demo, both backends run simultaneously to show failover. In production, you'd optimize the split based on latency requirements and cost targets.
