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

**8B fits on minimal hardware.** The model runs in FP16 on a single A10G (24GB VRAM) with room for KV cache. On Inferentia, it fits on 2 Neuron cores (inf2.xlarge). This keeps demo infrastructure costs low — no multi-GPU setups needed.

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

### Model Compilation

Inferentia requires models to be compiled ahead of time with the Neuron SDK. This is a one-time step:

```bash
# Using optimum-neuron to compile the model
optimum-cli export neuron \
  --model meta-llama/Llama-3.1-8B-Instruct \
  --task text-generation \
  --batch_size 1 \
  --sequence_length 4096 \
  --auto_cast_type bf16 \
  --num_cores 2 \
  --output ./llama-3.1-8b-neuron/
```

The compiled model is stored in S3 and mounted into the vLLM-Neuron Pod.

### Configuration

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm-neuron
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: vllm
          image: vllm/vllm-neuron:latest
          args:
            - --model=/models/llama-3.1-8b-neuron
            - --device=neuron
            - --max-model-len=4096
            - --enable-auto-tool-choice
            - --tool-call-parser=llama3_json
          ports:
            - containerPort: 8000
          resources:
            limits:
              aws.amazon.com/neuroncore: 2
            requests:
              cpu: "4"
              memory: "16Gi"
          volumeMounts:
            - name: model-store
              mountPath: /models
      tolerations:
        - key: aws.amazon.com/neuron
          operator: Exists
          effect: NoSchedule
      volumes:
        - name: model-store
          persistentVolumeClaim:
            claimName: neuron-model-pvc
```

### Requirements

| Resource | Value |
|----------|-------|
| Instance | inf2.xlarge |
| Neuron Cores | 2 |
| CPU | 4 vCPUs |
| RAM | 16 GB |
| Storage | 20 GB (compiled model) |
| Estimated cost | ~$0.76/hr on-demand |
| Compilation time | ~15-30 min (one-time) |

### Inferentia Limitations

- **Compilation is mandatory** — No JIT. If you change `max-model-len` or `batch_size`, you recompile.
- **Not all models compile** — Some architectures have unsupported operations. Llama 3.1 compiles cleanly.
- **Batch size is fixed at compile time** — Less flexible than GPU. For the demo (single user), batch_size=1 is fine.
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
| GPU (g5.xlarge) | 1x A10G | ~$1.01/hr | Universal compatibility, fastest time-to-first-token |
| Inferentia (inf2.xlarge) | 2 Neuron cores | ~$0.76/hr | 25% cheaper, requires compilation step |
| ARM (m7g.medium) | CPU only | ~$0.04/hr | For agent, MCP servers, gateway — no inference |

Running 24/7 for a month:
- GPU only: ~$727/mo
- Inferentia only: ~$547/mo (25% savings)
- Mixed (GPU primary + Inferentia fallback): depends on routing split

For the demo, both backends run simultaneously to show failover. In production, you'd optimize the split based on latency requirements and cost targets.
