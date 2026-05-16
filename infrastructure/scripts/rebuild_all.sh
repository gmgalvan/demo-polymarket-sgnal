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
run_terraform_apply "infrastructure/lv-3-cluster-services/observability/monitoring"
run_terraform_apply "infrastructure/lv-3-cluster-services/observability/logging"
run_terraform_apply "infrastructure/lv-3-cluster-services/observability/gpu-metrics"
run_terraform_apply "infrastructure/lv-3-cluster-services/observability/neuron-monitor"

run_terraform_apply "infrastructure/lv-4-inference-services/cert-manager"
run_terraform_apply "infrastructure/lv-4-inference-services/kserve"
run_terraform_apply "infrastructure/lv-4-inference-services/kuberay"

if [[ -n "${NGC_API_KEY}" ]]; then
  run_terraform_apply \
    "infrastructure/lv-4-inference-services/nim-operator" \
    -var="ngc_api_key=${NGC_API_KEY}"
else
  print_step "Skipping infrastructure/lv-4-inference-services/nim-operator because NGC_API_KEY is not set"
fi

run_terraform_apply "infrastructure/lv-5-app-observability/langfuse"
run_terraform_apply "infrastructure/lv-3-cluster-services/observability/tracing"

print_step "Rebuild complete"
