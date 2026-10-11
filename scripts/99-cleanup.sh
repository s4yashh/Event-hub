#!/usr/bin/env bash
# =============================================================================
# EventHub — FULL TEARDOWN (run ONLY after your demo/evaluation!)
# Deletes every billable resource. KEEPS IAM users/group/roles (free) so you
# can log in and rebuild later. Verify afterwards in Billing.
#
# Run: bash scripts/99-cleanup.sh
# =============================================================================
set -uo pipefail

REGION="${REGION:-ap-south-1}"
export AWS_DEFAULT_REGION="$REGION"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="$SCRIPT_DIR/state.env"
# shellcheck disable=SC1090
source "$STATE" 2>/dev/null || true
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

try() { "$@" >/dev/null 2>&1 || echo "   (skip: '$1' errored — may not exist; rerun the script later if needed)"; }

echo "== EventHub teardown =="

echo "[1/12] EC2 instance + volumes"
if [ -n "${INSTANCE_ID:-}" ]; then
  ROOT_VOLUME=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].BlockDeviceMappings[?DeviceName==`/dev/xvda`].Ebs.VolumeId | [0]' \
    --output text 2>/dev/null || echo "None")
  try aws ec2 terminate-instances --instance-ids "$INSTANCE_ID"
  aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" 2>/dev/null || true
  if [ -n "$ROOT_VOLUME" ] && [ "$ROOT_VOLUME" != "None" ]; then
    try aws ec2 delete-volume --volume-id "$ROOT_VOLUME"
  fi
fi

echo "[2/12] RDS instance + subnet group (takes several minutes)"
try aws rds delete-db-instance --db-instance-identifier eventhub-mysql \
  --skip-final-snapshot --delete-automated-backups
aws rds wait db-instance-deleted --db-instance-identifier eventhub-mysql 2>/dev/null || true
try aws rds delete-db-subnet-group --db-subnet-group-name eventhub-db-subnet-group

echo "[3/12] DynamoDB tables"
try aws dynamodb delete-table --table-name EventSeats
try aws dynamodb delete-table --table-name Registrations

echo "[4/12] SQS queues"
try aws sqs delete-queue --queue-url "https://sqs.${REGION}.amazonaws.com/${ACCOUNT_ID}/eventhub-registrations"
try aws sqs delete-queue --queue-url "https://sqs.${REGION}.amazonaws.com/${ACCOUNT_ID}/eventhub-registrations-dlq"

echo "[5/12] SNS topic"
try aws sns delete-topic --topic-arn "arn:aws:sns:${REGION}:${ACCOUNT_ID}:eventhub-notifications"

echo "[6/12] Step Functions state machine"
SM_ARN=$(aws ssm get-parameter --name /eventhub/state-machine-arn \
  --query Parameter.Value --output text 2>/dev/null || true)
if [ -n "${SM_ARN:-}" ]; then
  try aws stepfunctions delete-state-machine --state-machine-arn "$SM_ARN"
fi

