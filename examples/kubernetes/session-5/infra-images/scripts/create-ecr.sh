#!/usr/bin/env bash
# Creates the ECR repositories used by this demo, if they don't exist
# yet. Safe to run more than once.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

for repo in "${REPOS[@]}"; do
  if aws ecr describe-repositories --repository-names "$repo" --region "$AWS_REGION" >/dev/null 2>&1; then
    log "Repository '$repo' already exists, skipping creation."
  else
    log "Creating ECR repository '$repo'..."
    aws ecr create-repository \
      --repository-name "$repo" \
      --region "$AWS_REGION" \
      --image-scanning-configuration scanOnPush=true \
      --image-tag-mutability MUTABLE >/dev/null
    log "  Created '$repo'."
  fi

  # Re-applying tags is harmless, so we do it whether the repo is new
  # or already existed (keeps tags in sync with config.env either way).
  repo_arn="$(aws ecr describe-repositories \
    --repository-names "$repo" \
    --region "$AWS_REGION" \
    --query 'repositories[0].repositoryArn' \
    --output text)"

  aws ecr tag-resource \
    --resource-arn "$repo_arn" \
    --region "$AWS_REGION" \
    --tags \
      "Key=Project,Value=$PROJECT_TAG" \
      "Key=Component,Value=$repo" \
      "Key=Environment,Value=$ENVIRONMENT_TAG" \
      "Key=ManagedBy,Value=$MANAGED_BY_TAG"
  log "  Tagged '$repo' (Project=$PROJECT_TAG, Component=$repo, Environment=$ENVIRONMENT_TAG, ManagedBy=$MANAGED_BY_TAG)."
done

log "Registry: $ECR_REGISTRY"
