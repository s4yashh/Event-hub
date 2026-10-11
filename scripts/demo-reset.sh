#!/usr/bin/env bash
# EventHub — reset demo state before each practice run / demo.
# Seats: event 1 -> 2, event 2 -> 50, event 3 -> 0. Queues purged.
# Run: bash scripts/demo-reset.sh
set -euo pipefail

REGION="${REGION:-ap-south-1}"
export AWS_DEFAULT_REGION="$REGION"

seat() { # eventId seats
  aws dynamodb update-item --table-name EventSeats \
    --key "{\"eventId\":{\"S\":\"$1\"}}" \
    --update-expression "SET seatsAvailable = :n" \
    --expression-attribute-values "{\":n\":{\"N\":\"$2\"}}" >/dev/null
  echo "  event $1 -> $2 seats"
}

echo "resetting seats:"
seat 1 2
seat 2 50
seat 3 0

QURL=$(aws ssm get-parameter --name /eventhub/queue-url --query Parameter.Value --output text)
DLQURL="${QURL%-registrations}-registrations-dlq"
qlen() { # total visible + in-flight messages for a queue url
  aws sqs get-queue-attributes --queue-url "$1" \
    --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
    --query 'Attributes' --output text 2>/dev/null | awk '{print $1+$2}' || echo 0
}

if [ "$(qlen "$QURL")" != "0" ] || [ "$(qlen "$DLQURL")" != "0" ]; then
  aws sqs purge-queue --queue-url "$QURL" 2>/dev/null || true
  aws sqs purge-queue --queue-url "$DLQURL" 2>/dev/null || true
  echo "queues purged."
  echo "!! NOTE: SQS purge can delay NEW messages for up to ~60 s."
  echo "!! Start your demo talk (architecture slide, ~2 min) before the first live registration."
else
  echo "queues already empty - no purge needed (nothing to delay your demo)"
fi
echo "demo state ready"
