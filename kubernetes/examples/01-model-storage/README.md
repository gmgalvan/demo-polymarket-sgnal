# ex-model-storage

Example manifests demonstrating different strategies for bringing LLM model data into Kubernetes pods. Each file corresponds to a strategy described in [docs/model-data-summary.md](../../docs/model-data-summary.md).

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

Terraform code: [`infrastructure/lv-3-cluster-services/efs/`](../../infrastructure/lv-3-cluster-services/efs/)

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
kubectl apply -f kubernetes/ex-model-storage/01-emptydir-download.yaml -n ai-example
```

## Strategy 2: PersistentVolume with EFS

Model is downloaded once by an init-container into an EFS-backed PV, then mounted read-only by all replicas.

Infrastructure required:
- EFS filesystem + mount targets ([`infrastructure/lv-3-cluster-services/efs/`](../../infrastructure/lv-3-cluster-services/efs/))
- EFS CSI driver (installed by the Terraform above)
- StorageClass `efs-sc` (created by the Terraform above)

```bash
kubectl apply -f kubernetes/ex-model-storage/02-pv-efs.yaml -n ai-example
```

Key details:
- Init-container skips download if model already exists on PV
- vLLM mounts PV as `readOnly: true` (enables OS page cache, zero lock contention)
- Multiple replicas share the same model data
- First pod downloads the model (~1-2 min for 6GB); subsequent pods start immediately

## Strategy 3: Modelcars (KServe)

Not included as a standalone manifest. Requires KServe `InferenceService` CRD with `storageUri: oci://` and `shareProcessNamespace: true`. See the [KServe documentation](https://kserve.github.io/website/) for details.

The modelcar approach uses a sidecar container that holds the OCI model image and creates a symlink via `/proc` filesystem to a shared `emptyDir`. Near-zero memory overhead but requires process namespace sharing.

Infrastructure required: KServe operator + OCI model image in ECR

## Strategy 4: OCI Image Volume Mount (K8s 1.31+)

The model is packaged as an OCI image and mounted directly as a native Kubernetes volume. No init-containers, no symlinks, no copying.

Infrastructure required:
- Kubernetes 1.31+ with `ImageVolume` feature gate enabled
- containerd 2.0+ or CRI-O 1.33+
- Model packaged and pushed as an OCI image to ECR

Building the model image:

```bash
# Download model
huggingface-cli download Qwen/Qwen2.5-3B-Instruct --local-dir ./qwen25-3b

# Package as OCI image with crane
crane append \
  --new_tag $ACCOUNT.dkr.ecr.$REGION.amazonaws.com/models/qwen25-3b:v1 \
  --new_layer <(tar -C ./qwen25-3b -cf - .) \
  --platform linux/amd64
```

```bash
kubectl apply -f kubernetes/ex-model-storage/03-oci-volume-mount.yaml -n ai-example
```

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
