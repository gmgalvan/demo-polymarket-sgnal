#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AWS_REGION="${AWS_REGION:-us-east-1}"
PRINCIPAL_ARN="${PRINCIPAL_ARN:-$(aws sts get-caller-identity --query Arn --output text)}"
MASTER_USER_ARN="${MASTER_USER_ARN:-$PRINCIPAL_ARN}"
NGC_API_KEY="${NGC_API_KEY:-}"

print_step() {
  printf '\n[STEP] %s\n' "$1"
}

run_terraform_apply() {
  local stack_dir="$1"
  shift

  print_step "Applying ${stack_dir}"
  (
    cd "${ROOT_DIR}/${stack_dir}"
    terraform init -reconfigure
    terraform apply -auto-approve "$@"
  )
}

print_step "Using AWS region ${AWS_REGION}"
print_step "Using principal ${PRINCIPAL_ARN}"

run_terraform_apply "infrastructure/lv-0-networking/vpc"

run_terraform_apply \
  "infrastructure/lv-2-core-compute/eks" \
  -var="cluster_admin_principal_arns=[\"${PRINCIPAL_ARN}\"]"

run_terraform_apply \
  "infrastructure/lv-2-core-compute/opensearch" \
  -var="master_user_arn=${MASTER_USER_ARN}"

run_terraform_apply "infrastructure/lv-3-cluster-services/efs"
run_terraform_apply "infrastructure/lv-3-cluster-services/karpenter"
run_terraform_apply "infrastructure/lv-3-cluster-services/observability"

if [[ -n "${NGC_API_KEY}" ]]; then
  run_terraform_apply \
    "infrastructure/lv-4-inference-services" \
    -var="ngc_api_key=${NGC_API_KEY}"
else
  run_terraform_apply \
    "infrastructure/lv-4-inference-services" \
    -var="install_nim_operator=false"
fi

print_step "Rebuild complete"
