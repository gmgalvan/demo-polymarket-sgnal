#!/usr/bin/env bash
# Tears down the ECR repositories. On purpose this does NOT use
# `aws ecr delete-repository --force` (which deletes a repo even if it
# still has images). Instead, for each repo:
#   1. list every image (tagged and untagged)
#   2. batch-delete all of them
#   3. only then delete the now-empty repository
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

if [[ "${FORCE:-}" != "yes" ]]; then
  read -r -p "This will permanently delete images + repositories: ${REPOS[*]} (region $AWS_REGION). Type 'yes' to continue: " reply
  if [[ "$reply" != "yes" ]]; then
    warn "Aborted."
    exit 1
  fi
fi

for repo in "${REPOS[@]}"; do
  if ! aws ecr describe-repositories --repository-names "$repo" --region "$AWS_REGION" >/dev/null 2>&1; then
    log "Repository '$repo' does not exist, skipping."
    continue
  fi

  log "Cleaning images in '$repo'..."

  # A multi-arch manifest list references per-platform manifests and
  # attestation manifests that are stored as separate, independently
  # addressable images. Right after a push, `list-images` doesn't
  # always surface all of them in one shot (and deleting the manifest
  # list can reveal more that were hidden behind it), so we loop
  # list -> batch-delete until the repo actually reports empty instead
  # of trusting a single pass.
  attempt=0
  while :; do
    image_ids="$(aws ecr list-images --repository-name "$repo" --region "$AWS_REGION" --query 'imageIds' --output json)"

    if [[ "$image_ids" == "[]" ]]; then
      log "  '$repo' is empty."
      break
    fi

    attempt=$((attempt + 1))
    if (( attempt > 5 )); then
      err "Gave up cleaning '$repo' after $attempt attempts; images remain."
      exit 1
    fi

    aws ecr batch-delete-image \
      --repository-name "$repo" \
      --region "$AWS_REGION" \
      --image-ids "$image_ids" >/dev/null
    log "  Deleted $(echo "$image_ids" | grep -c imageDigest) image(s) (pass $attempt)."
  done

  log "Deleting empty repository '$repo'..."
  aws ecr delete-repository --repository-name "$repo" --region "$AWS_REGION" >/dev/null
  log "  Deleted '$repo'."
done

log "Done."
