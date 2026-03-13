# EKS (lv-2 core compute)

This stack creates:

- An EKS cluster in the VPC created by `lv-0-networking/vpc` (via remote state).
- Karpenter IAM + interruption queue from the EKS module, and Karpenter chart via Helm.
- Three managed node groups:
  - `core` (default control workloads).
  - `l40s` with `g6e.xlarge` (L40S GPU) and desired size `1`.
  - `inferentia` with `inf2.xlarge` and desired size `1`.

Implementation detail:

- Root stack (`lv-2-core-compute/eks`) only wires inputs/outputs.
- Reusable modules live in:
  - `infrastructure/modules/eks-cluster`
  - `infrastructure/modules/eks-karpenter`

## Default assumptions

- Region: `us-east-1`
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

If your account/region has limited `g6e` quota or availability, override:

```bash
terraform apply -var='l40s_instance_type=g6e.2xlarge'
```

If your account/region has limited `inf2` quota or availability, override:

```bash
terraform apply -var='inferentia_instance_type=inf2.8xlarge'
```
