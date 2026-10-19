#!/usr/bin/env bash
# Restore the event catalog after all queue messages and workflows finish.
# This intentionally deletes demo registration records; run before a demo only.
set -euo pipefail

REGION="${REGION:-ap-south-1}"
export AWS_DEFAULT_REGION="$REGION"

QURL=$(aws ssm get-parameter --name /eventhub/queue-url --query Parameter.Value --output text)
SM_ARN=$(aws ssm get-parameter --name /eventhub/state-machine-arn --query Parameter.Value --output text)
DLQURL="${QURL%-registrations}-registrations-dlq"

queue_count() {
  local visible in_flight
  visible=$(aws sqs get-queue-attributes --queue-url "$1" \
    --attribute-names ApproximateNumberOfMessages \
    --query 'Attributes.ApproximateNumberOfMessages' --output text)
  in_flight=$(aws sqs get-queue-attributes --queue-url "$1" \
    --attribute-names ApproximateNumberOfMessagesNotVisible \
    --query 'Attributes.ApproximateNumberOfMessagesNotVisible' --output text)
  echo "$((visible + in_flight))"
}

if [ "$(queue_count "$QURL")" -ne 0 ]; then
  echo "Main queue still has messages. Wait for the worker before resetting." >&2
  exit 1
fi
RUNNING=$(aws stepfunctions list-executions --state-machine-arn "$SM_ARN" \
  --status-filter RUNNING --max-results 1 --query 'length(executions)' --output text)
if [ "$RUNNING" -ne 0 ]; then
  echo "A registration workflow is still running. Wait before resetting." >&2
  exit 1
fi

echo "Deleting old registration records (demo data)..."
REGISTRATION_KEYS=$(aws dynamodb scan --table-name Registrations \
  --projection-expression 'eventId,userId' \
  --query 'Items[*].[eventId.S,userId.S]' --output text)
while IFS=$'\t' read -r event_id user_id; do
  [ -n "$event_id" ] || continue
  aws dynamodb delete-item --table-name Registrations \
    --key "{\"eventId\":{\"S\":\"$event_id\"},\"userId\":{\"S\":\"$user_id\"}}" >/dev/null
done <<< "$REGISTRATION_KEYS"

for spec in '1 2' '2 50' '3 0' '4 36' '5 60' '6 24' '7 80' '8 45' '9 150' '10 1' '11 30' '12 0'; do
  read -r event_id seats <<< "$spec"
  aws dynamodb update-item --table-name EventSeats \
    --key "{\"eventId\":{\"S\":\"$event_id\"}}" \
    --update-expression 'SET seatsAvailable = :n' \
    --expression-attribute-values "{\":n\":{\"N\":\"$seats\"}}" >/dev/null
  echo "event $event_id: $seats seats"
done

if [ "$(queue_count "$DLQURL")" -ne 0 ]; then
  aws sqs purge-queue --queue-url "$DLQURL"
  echo "DLQ purged. Allow up to 60 seconds before using it again."
fi
echo "Demo state ready. Existing MySQL user accounts are retained."
