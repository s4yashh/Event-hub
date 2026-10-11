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

