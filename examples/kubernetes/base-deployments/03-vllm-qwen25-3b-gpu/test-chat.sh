#!/usr/bin/env bash

set -euo pipefail

# This script sends a simple OpenAI-compatible chat request to the vLLM
# service exposed by the GPU base deployment.
#
# Expected setup:
# 1. The deployment is already Running and Ready.
# 2. You already started:
#    kubectl port-forward -n demo-examples svc/vllm-gpu-qwen25 8000:8000
#
# Optional:
#   BASE_URL=http://127.0.0.1:8000 ./test-chat.sh

BASE_URL="${BASE_URL:-http://127.0.0.1:8000}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REQUEST_FILE="${SCRIPT_DIR}/request.chat-test.json"

echo "Checking vLLM health at ${BASE_URL}/health ..."
curl -fsS "${BASE_URL}/health"
echo
echo

echo "Sending a simple chat completion request to ${BASE_URL}/v1/chat/completions ..."
curl -sS "${BASE_URL}/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d @"${REQUEST_FILE}"
echo
