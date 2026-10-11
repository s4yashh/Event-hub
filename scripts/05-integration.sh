#!/usr/bin/env bash
# =============================================================================
# EventHub build — STEP 5: integration (SQS + DLQ, SNS, Step Functions, worker)
# Run: bash scripts/05-integration.sh
# =============================================================================
set -euo pipefail

REGION="${REGION:-ap-south-1}"
export AWS_DEFAULT_REGION="$REGION"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="$SCRIPT_DIR/state.env"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)/.."
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
KEY_FILE="$PROJECT_DIR/eventhub-key.pem"
# shellcheck disable=SC1090
source "$STATE"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
SSH_OPTS=(-i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8)
EMAILS=(you@example.com)

echo "== EventHub integration build =="

# ---- 1. SQS: DLQ + main queue with redrive policy ---------------------------
DLQ_URL=$(aws sqs get-queue-url --queue-name eventhub-registrations-dlq \
  --query QueueUrl --output text 2>/dev/null || echo "None")
if [ "$DLQ_URL" = "None" ]; then
  DLQ_URL=$(aws sqs create-queue --queue-name eventhub-registrations-dlq \
    --query QueueUrl --output text)
  echo "[1/5] DLQ created"
else
  echo "[1/5] DLQ exists"
fi

