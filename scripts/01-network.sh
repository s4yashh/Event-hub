#!/usr/bin/env bash
# =============================================================================
# EventHub build — STEP 1: network (VPC, subnets, IGW, route tables, security
# groups, RDS DB subnet group).  COST: $0 (nothing here can bill you).
#
# RUN FROM YOUR MAC, in the project folder, with your AWS CLI configured:
#   aws configure        (region ap-south-1, output json)
#   bash scripts/01-network.sh
#
# Safe to re-run: every resource is looked up by Name tag first.
# =============================================================================
set -euo pipefail

REGION="${REGION:-ap-south-1}"
export AWS_DEFAULT_REGION="$REGION"
EXPECTED_ACCOUNT="061039790916"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="$SCRIPT_DIR/state.env"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "== EventHub network build =="
echo "Account : $ACCOUNT_ID   Region: $REGION"
if [ "$ACCOUNT_ID" != "$EXPECTED_ACCOUNT" ]; then
  read -r -p "!! Account differs from expected ($EXPECTED_ACCOUNT). Type 'yes' to continue: " a
  [ "$a" = "yes" ] || { echo "Aborted."; exit 1; }
fi

# ---- 1. VPC ----------------------------------------------------------------
VPC_ID=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=eventhub-vpc \
  --query 'Vpcs[0].VpcId' --output text)
if [ "$VPC_ID" = "None" ]; then
  VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=eventhub-vpc}]' \
    --query 'Vpc.VpcId' --output text)
  aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames
  echo "[1/7] VPC created: $VPC_ID"
else
  echo "[1/7] VPC exists: $VPC_ID"
fi

