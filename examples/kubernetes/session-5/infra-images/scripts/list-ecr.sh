#!/usr/bin/env bash
# Quick status check: does each repo exist, and what's in it.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

for repo in "${REPOS[@]}"; do
  echo "=== $repo ==="
  if ! aws ecr describe-repositories --repository-names "$repo" --region "$AWS_REGION" >/dev/null 2>&1; then
    echo "  (repository does not exist)"
    continue
  fi
  aws ecr list-images \
    --repository-name "$repo" \
    --region "$AWS_REGION" \
    --query 'imageIds[*].{Tag:imageTag,Digest:imageDigest}' \
    --output table
done
