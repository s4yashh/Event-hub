#!/usr/bin/env bash
# =============================================================================
# EventHub build — STEP 4: deploy the web app to EC2
#   * waits for RDS to become available, stores /eventhub/db-host
#   * copies app/ to the instance, runs setup.sh (venv + systemd + start)
#   * loads schema.sql + seed.sql into RDS (credentials fetched on the
#     instance via its IAM role — no passwords travel through this script)
#   * verifies the web app answers on port 80
# Run: bash scripts/04-deploy.sh
# =============================================================================
set -euo pipefail

REGION="${REGION:-ap-south-1}"
export AWS_DEFAULT_REGION="$REGION"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="$SCRIPT_DIR/state.env"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KEY_FILE="$PROJECT_DIR/eventhub-key.pem"
# shellcheck disable=SC1090
source "$STATE"

SSH_OPTS=(-i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8)

echo "== EventHub deploy =="

