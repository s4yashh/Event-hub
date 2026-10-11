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

# ---- 3. Step Functions state machine ----------------------------------------
SM_ARN=$(aws stepfunctions list-state-machines \
  --query "stateMachines[?name=='eventhub-register'].stateMachineArn" --output text)
if [ -z "$SM_ARN" ]; then
  SM_ARN=$(aws stepfunctions create-state-machine \
    --name eventhub-register \
    --definition "file://$PROJECT_DIR/aws/stepfunctions/rendered/register-event.asl.json" \
    --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/CloudProject-StepFunctions-Role" \
    --query stateMachineArn --output text)
  echo "[3/5] state machine created"
else
  echo "[3/5] state machine exists"
fi

# ---- 4. SSM params + start the worker ---------------------------------------
for KV in "queue-url=$Q_URL" "sns-topic-arn=$TOPIC_ARN" "state-machine-arn=$SM_ARN"; do
  aws ssm put-parameter --name "/eventhub/${KV%%=*}" --type String \
    --value "${KV#*=}" --overwrite >/dev/null
done
echo "[4/5] queue-url / sns-topic-arn / state-machine-arn stored in SSM"
ssh "${SSH_OPTS[@]}" "ec2-user@$EC2_IP" 'sudo systemctl restart worker && sleep 2 && systemctl is-active worker'

