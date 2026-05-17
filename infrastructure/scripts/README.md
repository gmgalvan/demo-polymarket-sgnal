# Infrastructure Scripts

This folder contains helper scripts for Terraform infrastructure operations.

## `init_backend.sh`

Creates, validates, checks, and destroys Terraform remote backend resources:
- S3 bucket (Terraform state storage)
- DynamoDB table (state locking)

## `rebuild_all.sh`

Applies all infrastructure stacks in dependency order:
- `lv-0-networking/vpc`
- `lv-1-security-and-config/secrets`
- `lv-2-core-compute/eks`
- `lv-2-core-compute/opensearch`
- `lv-3-cluster-services/efs`
- `lv-3-cluster-services/karpenter`
- `lv-3-cluster-services/nvidia-device-plugin`
- `lv-3-cluster-services/neuron-device-plugin`
- `lv-3-cluster-services/platform-observability/01-monitoring`
- `lv-3-cluster-services/platform-observability/02-logging`
- `lv-3-cluster-services/platform-observability/04-gpu-metrics`
- `lv-3-cluster-services/platform-observability/05-neuron-monitor`
- `lv-4-inference-services/cert-manager`
- `lv-4-inference-services/kserve`
- `lv-4-inference-services/kuberay`
- `lv-4-inference-services/nim-operator` when `NGC_API_KEY` is set
- `lv-5-app-observability/01-langfuse`
- `lv-3-cluster-services/platform-observability/03-tracing`

It auto-detects the current AWS principal for:
- `cluster_admin_principal_arns`
- `master_user_arn`

If `NGC_API_KEY` is not set, it skips `lv-4-inference-services/nim-operator`.

## `destroy_all.sh`

Destroys all infrastructure stacks in reverse dependency order:
- `lv-4-inference-services/nim-operator`
- `lv-4-inference-services/kuberay`
- `lv-4-inference-services/kserve`
- `lv-4-inference-services/cert-manager`
- `lv-3-cluster-services/platform-observability/03-tracing`
- `lv-5-app-observability/01-langfuse`
- `lv-3-cluster-services/platform-observability/05-neuron-monitor`
- `lv-3-cluster-services/platform-observability/04-gpu-metrics`
- `lv-3-cluster-services/platform-observability/02-logging`
- `lv-3-cluster-services/platform-observability/01-monitoring`
- `lv-3-cluster-services/neuron-device-plugin`
- `lv-3-cluster-services/nvidia-device-plugin`
- `lv-3-cluster-services/karpenter`
- `lv-3-cluster-services/efs`
- `lv-2-core-compute/opensearch`
- `lv-2-core-compute/eks`
- `lv-1-security-and-config/secrets`
- `lv-0-networking/vpc`

## Prerequisites

- AWS CLI installed
- AWS credentials configured and valid
- Permissions to manage:
  - S3 buckets and policies
  - DynamoDB tables
  - IAM calls used by `sts get-caller-identity`

Optional:
- Set a profile before running:

```bash
export AWS_PROFILE=your-profile
```

## Usage

From repository root:

```bash
bash infrastructure/scripts/init_backend.sh <command>
bash infrastructure/scripts/rebuild_all.sh
bash infrastructure/scripts/destroy_all.sh
```

Commands:

- `status`: Show current backend resource status
- `create`: Create/configure backend resources
- `validate`: Validate access to backend resources
- `destroy`: Delete backend resources (interactive confirmations)
- `help`: Show script help

Examples:

```bash
bash infrastructure/scripts/init_backend.sh status
bash infrastructure/scripts/init_backend.sh create
bash infrastructure/scripts/init_backend.sh validate
bash infrastructure/scripts/rebuild_all.sh
bash infrastructure/scripts/destroy_all.sh
```

## Typical Workflow

1. Check identity and current backend state:

```bash
aws sts get-caller-identity
bash infrastructure/scripts/init_backend.sh status
```

2. Create backend:

```bash
bash infrastructure/scripts/init_backend.sh create
```

3. Initialize Terraform in your target stack:

```bash
cd infrastructure/lv-0-networking/vpc
terraform init
```

4. Validate backend access if needed:

```bash
bash infrastructure/scripts/init_backend.sh validate
```

5. Rebuild all stacks:

```bash
bash infrastructure/scripts/rebuild_all.sh
```

6. Destroy all stacks:

```bash
bash infrastructure/scripts/destroy_all.sh
```

## Notes

- Script configuration values are currently hardcoded near the top of
  [`init_backend.sh`](./init_backend.sh):
  - `BUCKET_NAME`
  - `DYNAMODB_TABLE`
  - `AWS_REGION`
  - `ENVIRONMENT`
  - `PROJECT`
- Update those values before running `create` if your environment differs.
- `destroy` is destructive and asks for explicit confirmation.
- `rebuild_all.sh` and `destroy_all.sh` use the current caller ARN by default.
- `lv-3/observability`, `lv-4`, and `lv-5` are split into separate stacks under their respective directories.
- Override values when needed:

```bash
export PRINCIPAL_ARN=arn:aws:iam::<account-id>:role/<role>
export MASTER_USER_ARN="$PRINCIPAL_ARN"
export NGC_API_KEY=nvapi-xxxx
```
