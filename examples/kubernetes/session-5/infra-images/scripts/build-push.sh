#!/usr/bin/env bash
# Builds both images (multi-arch: amd64 + arm64) and pushes them to ECR.
# Requires the repositories to already exist (run create-ecr.sh first).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

log "Logging in to $ECR_REGISTRY..."
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY" >/dev/null

BUILDER_NAME="infra-images-builder"
if ! docker buildx inspect "$BUILDER_NAME" >/dev/null 2>&1; then
  log "Creating buildx builder '$BUILDER_NAME' for $PLATFORMS..."
  docker buildx create --name "$BUILDER_NAME" --use >/dev/null
else
  docker buildx use "$BUILDER_NAME"
fi

log "Building + pushing $BACKEND_REPO ($PLATFORMS)..."
docker buildx build \
  --platform "$PLATFORMS" \
  -t "$ECR_REGISTRY/$BACKEND_REPO:$IMAGE_TAG" \
  "$BACKEND_PATH" \
  --push

log "Building + pushing $FRONTEND_REPO ($PLATFORMS)..."
docker buildx build \
  --platform "$PLATFORMS" \
  --build-arg VITE_API_URL="$VITE_API_URL" \
  -t "$ECR_REGISTRY/$FRONTEND_REPO:$IMAGE_TAG" \
  "$FRONTEND_PATH" \
  --push

log "Done. Pushed:"
log "  $ECR_REGISTRY/$BACKEND_REPO:$IMAGE_TAG"
log "  $ECR_REGISTRY/$FRONTEND_REPO:$IMAGE_TAG"
