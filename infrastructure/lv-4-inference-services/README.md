# lv-4 — Inference Services

This stack installs inference controllers on top of the existing EKS cluster.
It reads cluster credentials from `lv-2-core-compute/eks` remote state.

**Dependencies (must be applied first):**

```
lv-2-core-compute/eks      ← EKS cluster
lv-3-cluster-services/karpenter  ← Karpenter + NVIDIA/Neuron device plugins + NodePools
```

## What gets installed

| Controller | Namespace | Purpose |
|---|---|---|
| **cert-manager** | `cert-manager` | TLS certs for KServe webhooks |
| **KServe** | `kserve` | InferenceService CRD — declarative model serving with autoscaling |
| **KubeRay** | `kuberay-system` | RayCluster/RayJob/RayService CRDs — distributed Ray workloads |
| **NVIDIA NIM Operator** | `nim-operator` | NIMService CRD — deploy pre-optimized NVIDIA NIM containers |

## Pre-requisites

### 1. AWS credentials

```bash
aws sts get-caller-identity   # confirm you are authenticated
aws eks update-kubeconfig --region us-east-1 --name 352-demo-dev-eks
kubectl get nodes             # should show ARM + GPU + inf2 nodes
```

### 2. NVIDIA NGC API key (NIM Operator only)

The NIM Operator pulls model containers from `nvcr.io` (NVIDIA GPU Cloud).
You need an NGC API key to authenticate.

**How to get it:**

1. Create a free account at https://ngc.nvidia.com
2. Go to **Account menu → Setup → Generate Personal Key**
3. Select scopes: `NGC Catalog` (to pull NIM containers)
4. Copy the key — it starts with `nvapi-`

**The key is used for two things:**
- Authenticating to `nvcr.io` to pull NIM container images
- Downloading model weights from NGC at runtime (inside the NIM container)

**Never commit the key.** Pass it at apply time:

```bash
# Option A: inline
terraform apply -var="ngc_api_key=nvapi-xxxx..."

# Option B: tfvars file (add lv-4.auto.tfvars to .gitignore)
echo 'ngc_api_key = "nvapi-xxxx..."' > lv-4.auto.tfvars
terraform apply
```

Terraform stores it as a Kubernetes Secret `ngc-api-secret` in the
`nim-operator` namespace. NIMService resources reference this secret by name.

## Usage

### Full install (all controllers)

```bash
cd infrastructure/lv-4-inference-services

terraform init
terraform plan
terraform apply -var="ngc_api_key=nvapi-xxxx..."
```

### Selective install

```bash
# Only KubeRay — skip KServe and NIM
terraform apply \
  -var="install_kserve=false" \
  -var="install_cert_manager=false" \
  -var="install_nim_operator=false"

# Only KServe + cert-manager
terraform apply \
  -var="install_kuberay=false" \
  -var="install_nim_operator=false"
```

### Verify

```bash
kubectl get pods -n cert-manager
kubectl get pods -n kserve
kubectl get pods -n kuberay-system
kubectl get pods -n nim-operator

# Confirm CRDs are registered
kubectl get crd | grep -E "kserve|ray|nim"
```

## After install — quick smoke tests

### KServe — deploy a test InferenceService

```bash
kubectl apply -f - <<EOF
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: sklearn-iris
  namespace: default
spec:
  predictor:
    sklearn:
      storageUri: gs://kfserving-examples/models/sklearn/1.0/model
EOF

kubectl get inferenceservice sklearn-iris
```

### KubeRay — launch a minimal RayCluster

```bash
kubectl apply -f - <<EOF
apiVersion: ray.io/v1
kind: RayCluster
metadata:
  name: test-cluster
spec:
  headGroupSpec:
    rayStartParams: {}
    template:
      spec:
        containers:
        - name: ray-head
          image: rayproject/ray:2.9.0
          resources:
            requests: {cpu: "1", memory: "2Gi"}
EOF

kubectl get raycluster test-cluster
```

### NIM Operator — list available NIM profiles

```bash
# Once a NIMCache is created, check available model profiles
kubectl get nimcache -A
kubectl get nimservice -A
```

## Destroy

```bash
cd infrastructure/lv-4-inference-services
terraform destroy
```

> Destroying lv-4 does NOT affect lv-2 or lv-3.
> CRDs installed by Helm are removed automatically when the Helm release is deleted.
