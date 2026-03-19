# EKS (lv-2 core compute)

This stack now owns only EKS base infrastructure:

- EKS control plane
- Managed node groups (`core`, `l40s`, `inferentia`)
- Karpenter AWS-side prerequisites from the EKS module (IAM role/profile + interruption queue)

Karpenter in-cluster resources were moved to:

- `infrastructure/lv-3-cluster-services/karpenter`

## Usage

```bash
cd infrastructure/lv-2-core-compute/eks
terraform init
terraform plan
terraform apply
```

## EKS Console Access (IAM principal)

If your current IAM user/role cannot see Kubernetes objects in the EKS console, pass that principal ARN in Terraform:

```bash
aws sts get-caller-identity

cd infrastructure/lv-2-core-compute/eks
terraform apply \
  -var='cluster_admin_principal_arns=["arn:aws:iam::<account-id>:role/YOUR_ADMIN_ROLE"]'
```

You can include multiple principals in the same list.

To grant access to your current IAM principal automatically:

```bash
CALLER_ARN=$(aws sts get-caller-identity --query Arn --output text)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

if [[ "$CALLER_ARN" == arn:aws:sts::*:assumed-role/* ]]; then
  ROLE_NAME=$(echo "$CALLER_ARN" | cut -d/ -f2)
  PRINCIPAL_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
else
  PRINCIPAL_ARN="$CALLER_ARN"
fi

cd infrastructure/lv-2-core-compute/eks
terraform apply -var="cluster_admin_principal_arns=[\"${PRINCIPAL_ARN}\"]"
```

If Console still shows no Kubernetes objects:

1. Check the principal in CloudShell from the same browser session:
   - `aws sts get-caller-identity --query Arn --output text`
2. If CloudShell is `root` but your Terraform/CLI access was granted to `user/infra`, add an access entry for `root` or log in with `user/infra`.
3. Validate IAM action permissions:

```bash
AWS_REGION=us-east-1
CLUSTER=<your-cluster-name>
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
PRINCIPAL_ARN=$(aws sts get-caller-identity --query Arn --output text)
CLUSTER_ARN=arn:aws:eks:${AWS_REGION}:${ACCOUNT_ID}:cluster/${CLUSTER}

aws iam simulate-principal-policy \
  --policy-source-arn "$PRINCIPAL_ARN" \
  --action-names eks:DescribeCluster eks:AccessKubernetesApi \
  --resource-arns "$CLUSTER_ARN"
```

## Notes

- Region: `us-east-1`
- Kubernetes version default: `1.34`
- `l40s` and `inferentia` managed node groups default to desired size `0`
- Remote state key:
  - `dev/lv-2-core-compute/eks/terraform.tfstate`

## Next Step (Karpenter)

After `lv-2` is applied, run:

```bash
cd infrastructure/lv-3-cluster-services/karpenter
terraform init
terraform plan
terraform apply
```

## Destroy

Destroy in reverse order:

1. `lv-3-cluster-services/karpenter`
2. `lv-2-core-compute/eks`
