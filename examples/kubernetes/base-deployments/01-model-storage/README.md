# 01-model-storage

Example manifests demonstrating different strategies for bringing LLM model data into Kubernetes pods. Each file corresponds to a strategy described in [docs/model-data-summary.md](../../../../docs/model-data-summary.md).

All examples use vLLM with `Qwen/Qwen2.5-3B-Instruct` on the GPU lane for consistency.

## Strategies

| File | Strategy | Storage | When to Use |
|---|---|---|---|
| `01-emptydir-download.yaml` | emptyDir + HF download | Ephemeral, per-pod | Dev/single replica, small models |
| `02-pv-efs.yaml` | PersistentVolume (EFS) | Shared, persistent | Multi-replica, moderate scale |
| `03-oci-volume-mount.yaml` | OCI Image Volume | Cached by container runtime | Future-proof, multi-model |

---

## Infrastructure Prerequisites

Strategies 2+ require storage infrastructure provisioned via Terraform before the K8s manifests can be applied.

### EFS (Strategy 2)

Terraform code: [`infrastructure/lv-3-cluster-services/efs/`](../../../../infrastructure/lv-3-cluster-services/efs/)

What it provisions:
- EFS filesystem (encrypted, elastic throughput)
- Mount targets in 3 AZs (private subnets)
- Security group allowing NFS (port 2049) from EKS nodes
- EFS CSI driver (Helm release + IRSA)
- StorageClass `efs-sc` for dynamic provisioning

```bash
cd infrastructure/lv-3-cluster-services/efs
terraform init
terraform plan
terraform apply
```

After `terraform apply` completes, verify the CSI driver is running:

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver
kubectl get storageclass efs-sc
```

### When to use EFS vs FSx for Lustre

Both are valid for shared model storage, but they serve different scales:

| | **EFS** | **FSx for Lustre** |
|---|---|---|
| **Protocol** | NFS (POSIX) | Lustre (parallel filesystem) |
| **Max throughput** | ~3-5 GB/s (elastic) | Up to 1 TB/s |
| **Latency** | ~ms | ~sub-ms |
| **Price** | ~$0.30/GB-month (elastic) | ~$0.14/GB-month (scratch) |
| **Setup** | Simple (CSI driver) | More config (fixed capacity, deploy type) |
| **S3 integration** | No | Yes (mounts S3 as filesystem, lazy-load) |
| **Best for** | 1-10 replicas, small-medium models | 10+ replicas, large models (70B+) |

**For this demo** (1-2 replicas, 6GB model): EFS is sufficient. The model is read once at startup and loaded into GPU memory — filesystem throughput only matters during the initial load.

**In production at scale**, the pattern is:

```
S3 (model registry) → FSx for Lustre (high-throughput cache) → vLLM pods (ReadOnlyMany)
```

FSx for Lustre can mount an S3 bucket as a filesystem. You upload the model to S3 once, and FSx serves it with local NVMe cache. This gives you:
- S3 durability + Lustre speed
- Lazy loading (files pulled from S3 on first access, cached locally)
- Hundreds of replicas reading the same model without bottleneck

FSx for Lustre infrastructure is not included in this repo but would follow the same Terraform pattern at `infrastructure/lv-3-cluster-services/fsx-lustre/`.

---

## Strategy 1: emptyDir Download

**This is what our existing examples use.** vLLM downloads the model from Hugging Face on every pod start into an `emptyDir` volume.

- No external storage needed
- Model re-downloaded on every restart
- One copy per replica

Infrastructure required: **None**

```bash
kubectl apply -f examples/kubernetes/base-deployments/01-model-storage/01-emptydir-download.yaml -n demo-examples
```

## Strategy 2: PersistentVolume with EFS

Model is downloaded once by an init-container into an EFS-backed PV, then mounted read-only by all replicas.

Infrastructure required:
- EFS filesystem + mount targets ([`infrastructure/lv-3-cluster-services/efs/`](../../../../infrastructure/lv-3-cluster-services/efs/))
- EFS CSI driver (installed by the Terraform above)
- StorageClass `efs-sc` (created by the Terraform above)

```bash
kubectl apply -f examples/kubernetes/base-deployments/01-model-storage/02-pv-efs.yaml -n demo-examples
```

Key details:
- Init-container skips download if model already exists on PV
- vLLM mounts PV as `readOnly: true` (enables OS page cache, zero lock contention)
- Multiple replicas share the same model data
- First pod downloads the model (~1-2 min for 6GB)
- A recreated pod should start faster because the model is already present on EFS
- Additional replicas can also reuse the same model data, but they still need separate GPU capacity and may remain `Pending` until Karpenter provisions another node

Why this uses an `initContainer`:

- The init container acts as a one-time bootstrap step for the shared model cache.
- It mounts the same EFS volume at `/models`, checks whether the model directory already exists, and only downloads the model if it is missing.
- This keeps the serving container focused on running vLLM instead of mixing model bootstrap logic into the runtime startup path.
- The example uses `python:3.11-slim` plus `huggingface_hub.snapshot_download(...)` inline because it is a simple, self-contained demo pattern that does not require building a separate downloader image.
- In a more productionized setup, the same idea could be implemented with a dedicated downloader image or a small checked-in script, but the behavior would be the same: populate EFS once, then reuse it across pod restarts.

Recommended demo validation flow:

```bash
# Deploy the example
kubectl apply -f examples/kubernetes/base-deployments/01-model-storage/02-pv-efs.yaml -n demo-examples

# Confirm the PVC is bound
kubectl get pvc -n demo-examples

# Validate persistence by restarting the workload
kubectl scale deployment/vllm-gpu-pv --replicas=0 -n demo-examples
kubectl scale deployment/vllm-gpu-pv --replicas=1 -n demo-examples
kubectl get pods -n demo-examples -w
```

This demonstrates the main benefit of the strategy without depending on a second GPU node being available immediately.

## Strategy 3: Modelcars (KServe)

Not included as a standalone manifest. Requires KServe `InferenceService` CRD with `storageUri: oci://` and `shareProcessNamespace: true`. See the [KServe documentation](https://kserve.github.io/website/) for details.

The modelcar approach uses a sidecar container that holds the OCI model image and creates a symlink via `/proc` filesystem to a shared `emptyDir`. Near-zero memory overhead but requires process namespace sharing.

Infrastructure required: KServe operator + OCI model image in ECR

## Strategy 4: OCI Image Volume Mount (Kubernetes 1.35+ recommended)

The model is packaged as an OCI image and mounted directly as a native Kubernetes volume. No init-containers, no symlinks, no copying.

Infrastructure required:
- Kubernetes 1.35+ recommended so `ImageVolume` is enabled by default
- containerd 2.0+ or CRI-O 1.33+
- Model packaged and pushed as an OCI image to ECR

Validation note:
- This strategy was not validated on the earlier EKS 1.34 setup because the `image` volume fields were dropped from the live Pod spec.
- This strategy was validated successfully on EKS 1.35, where the model OCI artifact mounted at `/models` and vLLM reached `1/1 Running`.

Building the model image:

About `crane`:
- `crane` is a lightweight OCI/registry CLI from Google's `go-containerregistry` project.
- Official project page: `https://github.com/google/go-containerregistry`
- `crane` command reference: `https://github.com/google/go-containerregistry/tree/main/cmd/crane`
- It is used here as a simple way to package a local model directory as an OCI artifact and push it to ECR without writing a full Dockerfile.

```bash
# Download model
hf download Qwen/Qwen2.5-3B-Instruct --local-dir ./qwen25-3b
```

Install `crane` (Linux x86_64 example):

```bash
curl -LO https://github.com/google/go-containerregistry/releases/latest/download/go-containerregistry_Linux_x86_64.tar.gz
tar -xzf go-containerregistry_Linux_x86_64.tar.gz crane
sudo mv crane /usr/local/bin/
crane version
```

Create the ECR repository and authenticate:

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export MODEL_REPO=models/qwen25-3b
export MODEL_IMAGE_URI=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${MODEL_REPO}:v1

aws ecr describe-repositories --repository-names ${MODEL_REPO} --region ${AWS_REGION} || \
aws ecr create-repository --repository-name ${MODEL_REPO} --region ${AWS_REGION}

aws ecr get-login-password --region ${AWS_REGION} | \
crane auth login ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com -u AWS --password-stdin
```

Package and push the model as an OCI artifact:

```bash
crane append \
  --new_tag ${MODEL_IMAGE_URI} \
  --new_layer <(tar -C ./qwen25-3b -cf - .) \
  --platform linux/amd64
```

Verify the image exists:

```bash
aws ecr list-images --repository-name ${MODEL_REPO} --region ${AWS_REGION}
```

For a quick demo, you can avoid editing the manifest on disk and replace the placeholder inline:

```bash
sed 's|<AWS_ACCOUNT_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com/models/qwen25-3b:v1|023890853822.dkr.ecr.us-east-1.amazonaws.com/models/qwen25-3b:v1|' \
examples/kubernetes/base-deployments/01-model-storage/03-oci-volume-mount.yaml | kubectl apply -n demo-examples -f -
```

Recommended demo validation flow:

```bash
kubectl get pods -n demo-examples -w
kubectl scale deployment/vllm-gpu-oci --replicas=0 -n demo-examples
kubectl scale deployment/vllm-gpu-oci --replicas=1 -n demo-examples
```

Functional validation:

```bash
kubectl port-forward -n demo-examples deploy/vllm-gpu-oci 8000:8000

curl http://127.0.0.1:8000/health
curl http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d @/home/gmgalvan/demo-polymarket-sgnal/examples/kubernetes/base-deployments/03-vllm-qwen25-3b-gpu/request.chat-test.json
```

This validates the main idea of the strategy:
- no model downloader container
- no EFS dependency
- model delivered as an immutable OCI artifact
- runtime can reuse cached image layers on pod recreation

---

## Comparison

| | emptyDir | PV (EFS) | PV (FSx Lustre) | OCI Volume |
|---|---|---|---|---|
| **Cold start** | Slow (download every time) | Fast (after first download) | Fast (lazy-load from S3) | Fast (cached by runtime) |
| **Storage per replica** | Full copy each | Shared | Shared | Cached layers |
| **Multi-replica** | Wasteful | Efficient | Very efficient at scale | Efficient |
| **Max throughput** | N/A (network download) | ~3-5 GB/s | Up to 1 TB/s | Depends on runtime cache |
| **Setup complexity** | None | EFS + CSI driver | FSx + S3 + CSI driver | K8s 1.31+ feature gate |
| **Model versioning** | HF revision | Manual | S3 object versions | OCI tags |
| **LoRA layer sharing** | No | No | No | Yes (shared base layers) |
| **Infrastructure code** | — | `lv-3/efs/` | Not included (same pattern) | — |

### Decision guide

- **Dev / demo / single replica** → Strategy 1 (emptyDir). Zero setup.
- **Production, 2-10 replicas, small-medium models** → Strategy 2 (EFS). Simple, proven.
- **Production, 10+ replicas, large models (70B+)** → FSx for Lustre + S3. Maximum throughput.
- **Multi-model with LoRA variants** → Strategy 4 (OCI Volume). Layer sharing = storage savings.

## Note

These are reference manifests for educational purposes. They are not wired into a `kustomization.yaml` because each strategy is independent and you would only deploy one at a time. Apply them directly with `kubectl apply -f`.
