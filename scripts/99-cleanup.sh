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

