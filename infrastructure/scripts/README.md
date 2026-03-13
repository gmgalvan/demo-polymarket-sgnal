# Infrastructure Scripts

This folder contains helper scripts for Terraform infrastructure operations.

## `init_backend.sh`

Creates, validates, checks, and destroys Terraform remote backend resources:
- S3 bucket (Terraform state storage)
- DynamoDB table (state locking)

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

