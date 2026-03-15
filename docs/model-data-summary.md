# Model Data — Generative AI on Kubernetes

## The Core Challenge

Managing LLM model data is one of the most fundamental challenges on Kubernetes. Models range from ~14 GB (Mistral 7B) to ~800 GB (Llama 4 Maverick). Efficiently bringing this data into a cluster requires careful consideration of storage formats, registries, and access patterns.

---

## 1. Model Storage Formats

### Two Categories

**Weight-Only Formats** — Store only learned parameters (weights & biases). The runtime must already know the architecture to reconstruct the model.

- PyTorch State Dict (`.pt`, `.pth`) — De facto standard for LLM development
- TensorFlow Checkpoints (`.ckpt`) — Declining relevance
- NumPy Arrays (`.npy`, `.npz`) — Too limited for modern LLMs

**Self-Contained (Mostly) Formats** — Bundle weights + metadata + partial architecture info. Easier to deploy but none are truly 100% self-contained as of 2026.

### The Big Three Formats for LLMs

| Format | Key Strength | Limitation |
|---|---|---|
| **Safetensors** | Secure serialization, zero-copy loading, sharding support | Missing tokenizer & architecture (needs `tokenizer.json` + `config.json`) |
| **GGUF** | Quantization (8-bit, 4-bit, 2-bit), single-file with tokenizer metadata | Tied to llama.cpp / vLLM runtimes |
| **ONNX** | Framework-independent, structured computational graph | Lacks tokenizer/vocabulary — unsuitable for LLMs in practice |

### Safetensors Deep Dive
- Developed by Hugging Face (2021), fixes pickle security vulnerabilities
- JSON header → tensor metadata (dtype, shape, byte offsets) → raw tensor data
- Supports **sharding**: large models split across multiple files with an index file (e.g., Llama 405B uses 30 shards)
- Enables **zero-copy loading** — tensors mapped directly to memory
- Now the default weight format on Hugging Face

### GGUF Deep Dive
- From the llama.cpp project (Georgi Gerganov)
- Optimized for **quantized inference** on CPUs and edge devices
- Single-file binary: magic number → metadata (architecture, quantization, token mappings) → quantized tensors
- Backward-compatible design — newer models work with older runtimes
- Now supported on both CPU and GPU by llama.cpp and vLLM

### The Holy Grail: True Model Portability
The goal is to treat models like OCI container images — self-contained, runtime-independent artifacts. The **CNCF ModelPack** specification (Sandbox, May 2025) is a standardization attempt in this direction. We're not there yet, but the ecosystem is converging.

### Critical Supporting Files
- **`tokenizer.json`** — Tokenization rules, vocabulary mapping, special tokens (BPE, etc.)
- **`config.json`** — Model architecture, hyperparameters (layers, attention heads, hidden sizes)
- These are de facto standards beyond the Hugging Face ecosystem

---

## 2. Model Registries

A model registry provides centralized management for models: versioning, governance, metadata, and discovery.

### Core Features
- Metadata management (accuracy, dataset lineage, benchmarks)
- Model discovery and search (filter by architecture, metrics, etc.)
- Version control (models + datasets)
- Lifecycle management (experimentation → staging → production → retirement)
- Access control and auditing
- CI/CD pipeline integration

### Four Key Registries

#### Hugging Face Model Hub
- 2M+ models, 310K+ LLMs (as of early 2026)
- Public, with Model Cards, interactive inference widget, REST API
- Great for discovery; limited for private/production use

#### MLflow Model Registry
- Linux Foundation project (created by Databricks, 2018)
- Central Tracking Server for experiments, metrics, model artifacts
- Programmatic registration via Python SDK + REST API
- Can generate OCI container images from models
- Not Kubernetes-native (no CRDs), but deployable on K8s via Helm
- MLflow 3.0+ added better LLM support: memory-efficient logging, Prompt Registry, AI gateway

#### Kubeflow Model Registry
- CNCF project, Kubernetes-native with CRDs and controllers
- Part of the broader Kubeflow ecosystem (Pipelines, Trainer, Katib, KServe)
- MySQL backend, REST API + Python SDK
- Integrates directly with KServe InferenceService via `model-registry://` URI scheme
- Deeper K8s integration than MLflow

#### OCI Registry
- Store full model data (not just metadata references) as OCI artifacts
- Leverages existing container infrastructure (Docker Hub, Quay.io, etc.)
- Provides versioning, immutability, efficient distribution
- Models packaged as "passive data images" — immutable packages of weights + configs
- Each model chunk can be a separate layer for parallel downloads and caching

---

## 3. Accessing Model Data in Kubernetes

### Storage Initializers (KServe)
KServe uses **init-containers** triggered by URI schemas to download model data before the runtime starts.

| Schema | Source |
|---|---|
| `s3://` | AWS S3 |
| `gs://` | Google Cloud Storage |
| `https://` | HTTP download |
| `pvc://` | PersistentVolumeClaim |
| `oci://` | OCI image (modelcar) |
| `model-registry://` | Kubeflow Registry |
| `hf://` | Hugging Face Hub |

Custom schemas can be added via `ClusterStorageContainer` CRD.

### Four Model Data Access Strategies

#### Strategy 1: Init-Container Copy (emptyDir)
- Init-container downloads/copies model data into a shared `emptyDir` volume
- Runtime container mounts the same volume
- **Pro**: Fastest inference (node-local I/O)
- **Con**: Wastes storage per replica, slow startup, data copied every pod restart

#### Strategy 2: PersistentVolumes (PV/PVC)
- Store model once on shared distributed filesystem (NFS, Ceph, EFS, etc.)
- Mount as `ReadOnlyMany` across all replicas
- **Pro**: Highest storage efficiency, fast startup (no copy), external management
- **Con**: Network latency on every read, struggles at hundreds of replicas
- Performance tip: read-only mounts enable aggressive OS caching + zero lock contention

#### Strategy 3: Modelcars (KServe)
- Sidecar container holds the OCI model image; creates a **symbolic link** via `/proc` filesystem to shared `emptyDir`
- Requires `shareProcessNamespace: true`
- **No data copy** — just a symlink; < 10 MB memory overhead
- **Pro**: Fast, layer sharing for LoRA fine-tuned models
- **Con**: Race conditions on startup, security implications (`shareProcessNamespace`), multi-arch complexity

#### Strategy 4: OCI Image Volume Mounts (K8s 1.31+)
- Native Kubernetes feature: mount OCI images directly as read-only volumes
- No symlinks, no process namespace sharing, no copying
- Supports `subPath` for mounting specific directories
- **Pro**: Cleanest approach, full layer caching, forward-compatible
- **Con**: Beta as of K8s 1.35, requires CRI-O 1.33+ or containerd 2.2.0+

### Comparison Table

| Approach | Storage Efficiency | Access Speed | Startup Time | Best For |
|---|---|---|---|---|
| Init-Container Copy | Low | Fast | Slow | Single replica, latency-sensitive |
| PersistentVolume | Highest | Moderate | Fast | Multi-replica, moderate scale |
| Modelcar | High | Fast | Moderate | Multiple models sharing base layers |
| OCI Volume Mount | High | Fast | Moderate | Future-proof native K8s integration |

---

## Key Takeaways for the Talk

1. **No format is truly self-contained** — Safetensors and GGUF are "mostly self-contained" and dominate the LLM space, but both still need external runtime knowledge.

2. **Safetensors + Hugging Face convention** (`tokenizer.json` + `config.json`) is the de facto production standard for distributing LLMs.

3. **GGUF shines for edge/CPU inference** thanks to built-in quantization (down to 2-bit).

4. **Model registries bridge experimentation and production** — Hugging Face for discovery, MLflow/Kubeflow for lifecycle management, OCI registries for storing actual model data.

5. **The OCI image approach is the future** — packaging models as OCI artifacts leverages the entire container ecosystem (registries, caching, versioning, layer sharing).

6. **LoRA fine-tuning + OCI layers = efficiency** — base model as shared layers, LoRA adapters as additional layers, massive storage savings when running many fine-tuned variants.

7. **OCI Volume Mounts will replace modelcars** — native K8s support (1.31+) eliminates the need for `shareProcessNamespace` hacks, but modelcars are the reliable bridge technology for now.

8. **Choose your access strategy by workload**: init-container copy for max performance, PVs for storage efficiency at moderate scale, OCI-based for multi-model deployments with layer sharing.

---

## Hands-On Examples

Working Kubernetes manifests for strategies 1, 2, and 4 are available in [`kubernetes/ex-model-storage/`](../kubernetes/ex-model-storage/). Each manifest deploys vLLM with Qwen2.5-3B on GPU using a different storage approach, with inline comments explaining the trade-offs.
