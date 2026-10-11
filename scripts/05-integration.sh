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

Q_URL=$(aws sqs get-queue-url --queue-name eventhub-registrations \
  --query QueueUrl --output text 2>/dev/null || echo "None")
if [ "$Q_URL" = "None" ]; then
  DLQ_ARN="arn:aws:sqs:${REGION}:${ACCOUNT_ID}:eventhub-registrations-dlq"
  cat > /tmp/queue-attrs.json <<EOF
{
  "VisibilityTimeout": "30",
  "RedrivePolicy": "{\"deadLetterTargetArn\":\"${DLQ_ARN}\",\"maxReceiveCount\":\"3\"}"
}
EOF
  Q_URL=$(aws sqs create-queue --queue-name eventhub-registrations \
    --attributes file:///tmp/queue-attrs.json --query QueueUrl --output text)
  echo "[1/5] main queue created (visibility 30, maxReceiveCount 3)"
else
  echo "[1/5] main queue exists"
fi
aws sqs get-queue-attributes --queue-url "$Q_URL" \
  --attribute-names RedrivePolicy VisibilityTimeout \
  --query 'Attributes' --output text

# ---- 2. SNS topic + email subscription --------------------------------------
TOPIC_ARN=$(aws sns create-topic --name eventhub-notifications --query TopicArn --output text)
for EMAIL in "${EMAILS[@]}"; do
  FOUND=$(aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" \
    --query "Subscriptions[?Endpoint=='$EMAIL'].SubscriptionArn" --output text)
  if [ -z "$FOUND" ]; then
    aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email \
      --notification-endpoint "$EMAIL" --query SubscriptionArn --output text
    echo "[2/5] subscribed $EMAIL (needs the confirmation click in the inbox!)"
  else
    echo "[2/5] $EMAIL already subscribed ($FOUND)"
  fi
done

