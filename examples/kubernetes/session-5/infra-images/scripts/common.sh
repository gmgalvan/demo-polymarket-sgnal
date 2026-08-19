#!/usr/bin/env bash
# Shared setup sourced by every script in this folder: loads config.env,
# resolves the ECR registry URL, and validates that each app directory
# actually exists before any AWS/Docker call is made.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../config.env
source "$INFRA_DIR/config.env"

command -v aws >/dev/null 2>&1 || { echo "aws CLI is required but not installed." >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "docker is required but not installed." >&2; exit 1; }

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

BACKEND_PATH="$(cd "$INFRA_DIR/$BACKEND_DIR" && pwd)"
FRONTEND_PATH="$(cd "$INFRA_DIR/$FRONTEND_DIR" && pwd)"

REPOS=("$BACKEND_REPO" "$FRONTEND_REPO")

log()  { printf '\033[1;34m[infra-images]\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m[infra-images]\033[0m %s\n' "$1"; }
err()  { printf '\033[1;31m[infra-images]\033[0m %s\n' "$1" >&2; }
