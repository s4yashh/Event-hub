#!/usr/bin/env bash
# =============================================================================
# EventHub build — STEP 2: data layer
#   * SSM parameters (db-user, db-name, db-password, flask-secret)
#   * DynamoDB tables EventSeats + Registrations (+ seat seed)
#   * RDS MySQL eventhub-mysql  (COST CLOCK STARTS HERE ≈ $0.017/h)
#
# Run: bash scripts/02-data.sh     (safe to re-run; never resets seats)
# =============================================================================
set -euo pipefail

REGION="${REGION:-ap-south-1}"
export AWS_DEFAULT_REGION="$REGION"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="$SCRIPT_DIR/state.env"
# shellcheck disable=SC1090
source "$STATE"

echo "== EventHub data build =="

# ---- 1. SSM parameters ------------------------------------------------------
aws ssm put-parameter --name /eventhub/db-user --type String \
  --value eventhubadmin --overwrite >/dev/null
aws ssm put-parameter --name /eventhub/db-name --type String \
  --value eventhub --overwrite >/dev/null

if aws ssm get-parameter --name /eventhub/db-password >/dev/null 2>&1; then
  echo "[1/4] db-password exists (keeping it)"
else
  DB_PASS=$(openssl rand -base64 24 | tr -d '/+=')
  aws ssm put-parameter --name /eventhub/db-password --type SecureString --value "$DB_PASS" >/dev/null
  echo "[1/4] db-password generated + stored as SecureString"
fi

if aws ssm get-parameter --name /eventhub/flask-secret >/dev/null 2>&1; then
  echo "      flask-secret exists (keeping it)"
else
  FLASK_SECRET=$(openssl rand -base64 36 | tr -d '/+=')
  aws ssm put-parameter --name /eventhub/flask-secret --type SecureString --value "$FLASK_SECRET" >/dev/null
  echo "      flask-secret generated + stored as SecureString"
fi

# ---- 2. DynamoDB tables -----------------------------------------------------
for T in EventSeats Registrations; do
  if aws dynamodb describe-table --table-name "$T" >/dev/null 2>&1; then
    echo "[2/4] table $T exists"
  else
    if [ "$T" = "EventSeats" ]; then
      aws dynamodb create-table --table-name EventSeats \
        --attribute-definitions AttributeName=eventId,AttributeType=S \
        --key-schema AttributeName=eventId,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST >/dev/null
    else
      aws dynamodb create-table --table-name Registrations \
        --attribute-definitions AttributeName=eventId,AttributeType=S AttributeName=userId,AttributeType=S \
        --key-schema AttributeName=eventId,KeyType=HASH AttributeName=userId,KeyType=RANGE \
        --billing-mode PAY_PER_REQUEST >/dev/null
    fi
    aws dynamodb wait table-exists --table-name "$T"
    echo "[2/4] table $T created"
  fi
done

COUNT=$(aws dynamodb scan --table-name EventSeats --select COUNT --query Count --output text)
if [ "$COUNT" = "0" ]; then
  aws dynamodb put-item --table-name EventSeats --item '{"eventId":{"S":"1"},"seatsAvailable":{"N":"2"}}'
  aws dynamodb put-item --table-name EventSeats --item '{"eventId":{"S":"2"},"seatsAvailable":{"N":"50"}}'
  aws dynamodb put-item --table-name EventSeats --item '{"eventId":{"S":"3"},"seatsAvailable":{"N":"0"}}'
  echo "      seeded EventSeats: event 1 = 2 seats, event 2 = 50, event 3 = 0"
else
  echo "      EventSeats already has items (not reseeding)"
fi

