#!/usr/bin/env bash
# =============================================================================
# EventHub build — STEP 3: compute (key pair + EC2 instance + wait until ready)
# Run: bash scripts/03-compute.sh
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

echo "== EventHub compute build =="

# ---- 1. key pair ------------------------------------------------------------
if [ ! -f "$KEY_FILE" ]; then
  EXISTING=$(aws ec2 describe-key-pairs --key-names eventhub-key \
    --query 'KeyPairs[0].KeyName' --output text 2>/dev/null || echo "None")
  if [ "$EXISTING" = "None" ]; then
    aws ec2 create-key-pair --key-name eventhub-key \
      --query 'KeyMaterial' --output text > "$KEY_FILE"
    chmod 400 "$KEY_FILE"
    echo "[1/4] key pair created -> $KEY_FILE"
  else
    echo "!! key pair 'eventhub-key' exists in AWS but the local .pem is missing."
    echo "   Delete the AWS key pair first (aws ec2 delete-key-pair --key-name eventhub-key) or restore the .pem."
    exit 1
  fi
else
  echo "[1/4] local key file found: $KEY_FILE"
fi

