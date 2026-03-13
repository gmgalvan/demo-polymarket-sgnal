# Karpenter (lv-3 cluster services)

This stack manages in-cluster Karpenter resources and accelerator plugins:

- Karpenter CRDs and controller via Helm
- NVIDIA and Neuron device plugins
- EC2NodeClass and NodePool resources for:
  - `arm-general`
  - `gpu-inference`
  - `neuron-inference`

It reads EKS connection and networking values from `lv-2-core-compute/eks` remote state.

Design goal:

- one `terraform apply` in this stack
- no phased `enable_karpenter_*` toggles in the command line

## Usage

```bash
cd infrastructure/lv-3-cluster-services/karpenter
terraform init
terraform plan
terraform apply
```

## Dependencies

`lv-2-core-compute/eks` must be applied first.

If `lv-2` was just created, run:

```bash
aws eks describe-cluster --name 352-demo-dev-eks --region us-east-1 --query 'cluster.status' --output text
aws eks update-kubeconfig --region us-east-1 --name 352-demo-dev-eks
kubectl get nodes
```

## Destroy

```bash
cd infrastructure/lv-3-cluster-services/karpenter
terraform destroy
```
