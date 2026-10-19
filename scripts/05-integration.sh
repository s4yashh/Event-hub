#!/usr/bin/env bash
# =============================================================================
# EventHub build — STEP 5: integration (SQS + DLQ, SNS, Step Functions, worker)
# Run: bash scripts/05-integration.sh
# =============================================================================
set -euo pipefail

REGION="${REGION:-ap-south-1}"
export AWS_DEFAULT_REGION="$REGION"
export AWS_PAGER=""
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="$SCRIPT_DIR/state.env"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)/.."
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
KEY_FILE="$PROJECT_DIR/eventhub-key.pem"
# shellcheck disable=SC1090
source "$STATE"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
SSH_OPTS=(-i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8)
# Optional space-separated team inboxes for workflow and alarm notifications.
# Student addresses are subscribed by the app during sign-up/registration.

# Render the account-specific SNS ARN from the tracked ASL template. The
# rendered copy is ignored by git and can be regenerated for any account.
RENDERED_DIR="$PROJECT_DIR/aws/stepfunctions/rendered"
mkdir -p "$RENDERED_DIR"
sed "s/<ACCOUNT_ID>/${ACCOUNT_ID}/g" \
  "$PROJECT_DIR/aws/stepfunctions/register-event.asl.json" \
  > "$RENDERED_DIR/register-event.asl.json"
python3 -m json.tool "$RENDERED_DIR/register-event.asl.json" >/dev/null

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

# ---- 2. Separate student ticket updates from operator alarms ---------------
TOPIC_ARN=$(aws sns create-topic --name eventhub-notifications --query TopicArn --output text)
ALERT_TOPIC_ARN=$(aws sns create-topic --name eventhub-alerts --query TopicArn --output text)
# Existing EC2 instances keep their IAM role, so refresh its inline policy when
# the app gains the ability to request student SNS email subscriptions.
sed "s/<ACCOUNT_ID>/${ACCOUNT_ID}/g" \
  "$PROJECT_DIR/aws/iam/ec2-role-policy.json" \
  > "$RENDERED_DIR/ec2-role-policy.json"
aws iam put-role-policy --role-name CloudProject-EC2-Role \
  --policy-name CloudProject-EC2-Policy \
  --policy-document "file://$RENDERED_DIR/ec2-role-policy.json"
echo "      EC2 role policy updated for student email subscriptions"
if [ -n "${DEMO_EMAILS:-}" ]; then
  read -r -a EMAILS <<< "$DEMO_EMAILS"
  for EMAIL in "${EMAILS[@]}"; do
    FOUND=$(aws sns list-subscriptions-by-topic --topic-arn "$ALERT_TOPIC_ARN" \
      --query "Subscriptions[?Endpoint=='$EMAIL'].SubscriptionArn" --output text)
    if [ -z "$FOUND" ]; then
      aws sns subscribe --topic-arn "$ALERT_TOPIC_ARN" --protocol email \
        --notification-endpoint "$EMAIL" --query SubscriptionArn --output text
      echo "[2/5] subscribed $EMAIL to operator alerts (confirm in inbox)"
    else
      echo "[2/5] $EMAIL already subscribed ($FOUND)"
    fi
  done
else
  echo "[2/5] no operator email configured; student subscriptions happen in the app"
fi
echo "      Student ticket topic: $TOPIC_ARN"
echo "      Operator alarm topic: $ALERT_TOPIC_ARN"
# Existing builds may have team inboxes subscribed without a filter. Restrict every
# confirmed email subscription to its own endpoint before new ticket publishes.
SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" \
  --query 'Subscriptions[*].[SubscriptionArn,Protocol,Endpoint]' --output text)
while IFS=$'\t' read -r SUB_ARN SUB_PROTOCOL SUB_ENDPOINT; do
  [ -n "$SUB_ARN" ] || continue
  if [ "$SUB_PROTOCOL" = "email" ] && [ "$SUB_ARN" != "PendingConfirmation" ]; then
    FILTER=$(python3 -c 'import json,sys; print(json.dumps({"email":[sys.argv[1]]}))' "$SUB_ENDPOINT")
    aws sns set-subscription-attributes --subscription-arn "$SUB_ARN" \
      --attribute-name FilterPolicy --attribute-value "$FILTER"
    echo "      restricted ticket subscription for $SUB_ENDPOINT"
  else
    echo "      REVIEW ticket subscription: $SUB_PROTOCOL $SUB_ENDPOINT ($SUB_ARN)"
  fi
done <<< "$SUBSCRIPTIONS"
echo "      Allow up to 15 minutes for ticket filters to take effect."

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
  aws stepfunctions update-state-machine \
    --state-machine-arn "$SM_ARN" \
    --definition "file://$RENDERED_DIR/register-event.asl.json" \
    --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/CloudProject-StepFunctions-Role" >/dev/null
  echo "[3/5] state machine updated"
fi

# ---- 4. SSM params + start the worker ---------------------------------------
for KV in "queue-url=$Q_URL" "sns-topic-arn=$TOPIC_ARN" "alerts-topic-arn=$ALERT_TOPIC_ARN" "state-machine-arn=$SM_ARN"; do
  aws ssm put-parameter --name "/eventhub/${KV%%=*}" --type String \
    --value "${KV#*=}" --overwrite >/dev/null
done
echo "[4/5] queue, ticket topic, alert topic, and workflow ARNs stored in SSM"
ssh "${SSH_OPTS[@]}" "ec2-user@$EC2_IP" 'sudo systemctl restart worker && sleep 2 && systemctl is-active worker'

# ---- 5. Smoke test: run the real workflow once ------------------------------
SMOKE_USER_ID="smoke-$(date +%s)-$$"
echo "[5/5] smoke test: starting one execution (event 2, user $SMOKE_USER_ID)"
SEATS_BEFORE=$(aws dynamodb get-item --table-name EventSeats \
  --key '{"eventId":{"S":"2"}}' --query 'Item.seatsAvailable.N' --output text)
if [ "$SEATS_BEFORE" = "None" ] || [ "$SEATS_BEFORE" -le 0 ]; then
  echo "Event 2 needs an available seat for this smoke test." >&2
  exit 1
fi
EXEC_ARN=$(aws stepfunctions start-execution \
  --state-machine-arn "$SM_ARN" \
  --input "{\"eventId\":\"2\",\"userId\":\"$SMOKE_USER_ID\",\"email\":\"smoke@test.local\",\"eventTitle\":\"Acoustic Night\",\"eventDate\":\"28 Nov 2026, 06:30 PM\",\"eventVenue\":\"Anna Auditorium\"}" \
  --query executionArn --output text)
STATUS=RUNNING
for _ in $(seq 1 30); do
  STATUS=$(aws stepfunctions describe-execution --execution-arn "$EXEC_ARN" \
    --query status --output text)
  [ "$STATUS" != "RUNNING" ] && break
  sleep 2
done
if [ "$STATUS" != "SUCCEEDED" ]; then
  echo "Smoke test did not succeed (status: $STATUS). Inspect $EXEC_ARN before resetting data."
  exit 1
fi
SEATS_AFTER=$(aws dynamodb get-item --table-name EventSeats \
  --key '{"eventId":{"S":"2"}}' --query 'Item.seatsAvailable.N' --output text)
TICKET_STATUS=$(aws dynamodb get-item --table-name Registrations \
  --key "{\"eventId\":{\"S\":\"2\"},\"userId\":{\"S\":\"$SMOKE_USER_ID\"}}" \
  --query 'Item.status.S' --output text)
if [ "$TICKET_STATUS" != "CONFIRMED" ] || [ "$SEATS_AFTER" -ne "$((SEATS_BEFORE - 1))" ]; then
  echo "Smoke test mismatch: ticket=$TICKET_STATUS, seats $SEATS_BEFORE -> $SEATS_AFTER." >&2
  exit 1
fi
echo "      ticket CONFIRMED; event 2 seats after smoke test: $SEATS_AFTER"

# reset demo state
aws dynamodb update-item --table-name EventSeats \
  --key '{"eventId":{"S":"2"}}' \
  --update-expression "SET seatsAvailable = :n" \
  --expression-attribute-values "{\":n\":{\"N\":\"$SEATS_BEFORE\"}}" >/dev/null
aws dynamodb delete-item --table-name Registrations \
  --key "{\"eventId\":{\"S\":\"2\"},\"userId\":{\"S\":\"$SMOKE_USER_ID\"}}" >/dev/null
echo "      smoke test data removed (event 2 back to $SEATS_BEFORE seats)"

echo
cat <<DONE
============================================================
INTEGRATION DONE
Queue:   $Q_URL
DLQ:     $DLQ_URL
Ticket topic: $TOPIC_ARN
Alarm topic:  $ALERT_TOPIC_ARN
State machine: $SM_ARN
Worker:  running on $EC2_IP
ACTION REQUIRED: confirm each demo student's ticket subscription and each operator alarm subscription.
============================================================
DONE
