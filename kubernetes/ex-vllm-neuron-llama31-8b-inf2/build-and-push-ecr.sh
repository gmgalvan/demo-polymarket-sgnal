#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
ECR_REPO="${ECR_REPO:-vllm-neuron}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
VLLM_REF="${VLLM_REF:-v0.6.0}"

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${IMAGE_TAG}"

echo "Using:"
echo "  AWS_REGION=${AWS_REGION}"
echo "  ECR_REPO=${ECR_REPO}"
echo "  IMAGE_TAG=${IMAGE_TAG}"
echo "  VLLM_REF=${VLLM_REF}"
echo "  IMAGE_URI=${IMAGE_URI}"

aws ecr describe-repositories --repository-names "${ECR_REPO}" --region "${AWS_REGION}" >/dev/null 2>&1 || \
  aws ecr create-repository --repository-name "${ECR_REPO}" --region "${AWS_REGION}" >/dev/null

aws ecr get-login-password --region "${AWS_REGION}" | \
  docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

docker build \
  --build-arg VLLM_REF="${VLLM_REF}" \
  -f Dockerfile.neuron \
  -t "${IMAGE_URI}" \
  .

docker push "${IMAGE_URI}"

echo
echo "Done. Image pushed:"
echo "  ${IMAGE_URI}"
echo
echo "Next:"
echo "  kubectl set image deployment/vllm-neuron-llama31-8b vllm-neuron=${IMAGE_URI} -n ai-example"
echo "  kubectl scale deployment/vllm-neuron-llama31-8b --replicas=1 -n ai-example"
