# EKS (lv-2 core compute)

This stack creates:

- An EKS cluster in the VPC created by `lv-0-networking/vpc` (via remote state).
- Karpenter IAM + interruption queue from the EKS module, and Karpenter chart via Helm.
- Three managed node groups:
  - `core` (default control workloads).
  - `l40s` with `g6e.xlarge` (L40S GPU) and desired size `0`.
  - `inferentia` with `inf2.xlarge` and desired size `0`.

Implementation detail:

- Root stack (`lv-2-core-compute/eks`) only wires inputs/outputs.
- Reusable modules live in:
  - `infrastructure/modules/eks-cluster`
  - `infrastructure/modules/eks-karpenter`

## Default assumptions

- Region: `us-east-1`
- Kubernetes: `1.34` (DRA-capable control plane on EKS)
- VPC remote state:
  - Bucket: `352-demo-dev-s3b-tfstate-backend`
  - Key: `dev/lv-0-networking/vpc/terraform.tfstate`
- EKS state:
  - Bucket: `352-demo-dev-s3b-tfstate-backend`
  - Key: `dev/lv-2-core-compute/eks/terraform.tfstate`

## Usage

```bash
cd infrastructure/lv-2-core-compute/eks
terraform init
terraform plan
terraform apply
```

## Quick Commands

Fresh build from zero:

```bash
cd infrastructure/lv-2-core-compute/eks
terraform init
terraform apply
aws eks update-kubeconfig --region us-east-1 --name 352-demo-dev-eks
terraform apply -var='enable_karpenter_resources=true'
terraform apply -var='enable_karpenter_resources=true' -var='enable_karpenter_nodepools=true'
```

Validation smoke test flow:

```bash
kubectl get nodes -o wide
kubectl get nodepools
kubectl get ec2nodeclasses
```

## Fresh Bootstrap

For a fresh cluster bootstrap, use three phases.

### Phase 1: EKS base

Create only the AWS-side resources first: EKS control plane, managed node groups, IAM, SQS, and networking attachments.

```bash
terraform apply
```

Expected result:

- EKS cluster exists.
- `core` node group is up.
- `l40s` and `inferentia` node groups exist with desired size `0`.
- Karpenter IAM/SQS resources exist in AWS, but no in-cluster Karpenter resources yet.

### Phase 2: Kubeconfig + Karpenter chart + CRDs + device plugins

Connect `kubectl` to the cluster, then install Karpenter, its CRDs, and the accelerator device plugins.

```bash
aws eks update-kubeconfig --region us-east-1 --name 352-demo-dev-eks
kubectl get nodes -o wide
terraform apply -var='enable_karpenter_resources=true'
```

Verify:

```bash
kubectl get pods -n kube-system
kubectl get crd | grep -E 'karpenter|nodepool|ec2nodeclass'
kubectl get daemonset -n kube-system
kubectl get deploy -n kube-system karpenter
```

Expected result:

- `karpenter` deployment exists in `kube-system`.
- CRDs exist:
  - `ec2nodeclasses.karpenter.k8s.aws`
  - `nodepools.karpenter.sh`
- NVIDIA and Neuron device plugin DaemonSets are installed.
- GPU and Inferentia plugin pods may still show `0` desired/current, because there are no accelerator nodes yet.

### Phase 3: EC2NodeClass + NodePool resources

After the Karpenter CRDs exist in the Kubernetes API, create the Karpenter scheduling resources.

```bash
terraform apply \
  -var='enable_karpenter_resources=true' \
  -var='enable_karpenter_nodepools=true'
```

Verify:

```bash
kubectl get nodepools
kubectl get ec2nodeclasses
kubectl describe nodepool arm-general
kubectl describe nodepool gpu-inference
kubectl describe nodepool neuron-inference
```

Expected result:

- `arm-general`, `gpu-inference`, and `neuron-inference` NodePools exist.
- `arm-general`, `gpu-inference`, and `neuron-inference` EC2NodeClasses exist.
- Only the `core` node is running initially.
- GPU and Inferentia nodes stay off until a workload requests them.

## Destroy And Rebuild

Destroy only the EKS stack:

```bash
cd infrastructure/lv-2-core-compute/eks
terraform destroy \
  -var='enable_karpenter_resources=true' \
  -var='enable_karpenter_nodepools=true'
```

Rebuild after destroy:

```bash
cd infrastructure/lv-2-core-compute/eks
terraform init
terraform apply
aws eks update-kubeconfig --region us-east-1 --name 352-demo-dev-eks
terraform apply -var='enable_karpenter_resources=true'
terraform apply -var='enable_karpenter_resources=true' -var='enable_karpenter_nodepools=true'
```

Full reset including the VPC:

```bash
cd infrastructure/lv-2-core-compute/eks
terraform destroy \
  -var='enable_karpenter_resources=true' \
  -var='enable_karpenter_nodepools=true'

cd ../../lv-0-networking/vpc
terraform destroy
```

Full rebuild after destroying the VPC:

```bash
cd infrastructure/lv-0-networking/vpc
terraform init
terraform apply

cd ../../lv-2-core-compute/eks
terraform init
terraform apply
aws eks update-kubeconfig --region us-east-1 --name 352-demo-dev-eks
terraform apply -var='enable_karpenter_resources=true'
terraform apply -var='enable_karpenter_resources=true' -var='enable_karpenter_nodepools=true'
```

## Why Multiple Applies?

This stack cannot be bootstrapped safely in a single `terraform apply` because each layer depends on the previous one being live:

1. Terraform must create the EKS cluster before the `kubernetes` and `helm` providers can connect.
2. Karpenter CRDs must exist before Terraform can create `EC2NodeClass` and `NodePool` objects.
3. Accelerator node pools should stay empty until matching workloads are deployed.

This is a normal bootstrap pattern when the same Terraform configuration creates both:

- infrastructure outside the cluster, and
- Kubernetes resources inside the cluster

## Notes

- `1.34` enables the core Kubernetes DRA APIs on EKS, but this stack still uses classic device-plugin scheduling for accelerators.
- For NVIDIA DRA you would move from the plain device plugin to NVIDIA's DRA/GPU Operator path.
- For AWS Neuron, the official DRA driver documentation is currently centered on Trainium, not `inf2`.
- One Karpenter replica may stay `Pending` on a single-node bootstrap. That is expected until you have more schedulable capacity.
- The NVIDIA device plugin is pinned by `nodeSelector=workload=gpu` and a GPU taint toleration, with the chart's default GPU-feature-discovery affinity disabled. This avoids a bootstrap deadlock on fresh Karpenter GPU nodes.
- The Karpenter `EC2NodeClass` resources now define larger root volumes:
  - `arm-general`: `40Gi`
  - `gpu-inference`: `200Gi`
  - `neuron-inference`: `150Gi`
- That change is intentional. The `vllm/vllm-openai:latest` image is large enough to exhaust the default root volume on fresh GPU nodes during image extraction.

If your account/region has limited `g6e` quota or availability, override:

```bash
terraform apply -var='l40s_instance_type=g6e.2xlarge'
```

If your account/region has limited `inf2` quota or availability, override:

```bash
terraform apply -var='inferentia_instance_type=inf2.8xlarge'
```
