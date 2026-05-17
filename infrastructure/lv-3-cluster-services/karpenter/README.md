# Karpenter (lv-3 cluster services)

This stack manages in-cluster Karpenter resources only:

- Karpenter CRDs and controller via Helm
- EC2NodeClass and NodePool resources for:
  - `arm-general`
  - `gpu-inference`
  - `neuron-inference`

Accelerator device plugins now live in:

- `infrastructure/lv-3-cluster-services/nvidia-device-plugin/`
- `infrastructure/lv-3-cluster-services/neuron-device-plugin/`

It reads EKS connection and networking values from `lv-2-core-compute/eks` remote state.

Design goal:

- keep Karpenter focused on node provisioning and pool definitions
- keep accelerator runtime plumbing separate from autoscaling logic

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
aws eks describe-cluster --name <your-cluster-name> --region us-east-1 --query 'cluster.status' --output text
aws eks update-kubeconfig --region us-east-1 --name <your-cluster-name>
kubectl get nodes
```

## Destroy

```bash
cd infrastructure/lv-3-cluster-services/karpenter
terraform destroy
```
