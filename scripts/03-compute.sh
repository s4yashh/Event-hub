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

# ---- 2. instance ------------------------------------------------------------
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters Name=tag:Name,Values=eventhub-web \
            "Name=instance-state-name,Values=pending,running,stopped" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)
if [ "$INSTANCE_ID" = "None" ]; then
  AMI_ID=$(aws ssm get-parameter \
    --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
    --query 'Parameter.Value' --output text)
  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type t3.micro \
    --key-name eventhub-key \
    --security-group-ids "$WEB_SG" \
    --subnet-id "$PUBLIC_SUBNET" \
    --associate-public-ip-address \
    --iam-instance-profile Name=CloudProject-EC2-Profile \
    --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=8,VolumeType=gp3,Encrypted=true}' \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=eventhub-web}]' \
    --query 'Instances[0].InstanceId' --output text)
  echo "[2/4] instance launched: $INSTANCE_ID"
else
  echo "[2/4] instance exists: $INSTANCE_ID"
fi

# ---- 3. wait until running + status checks green ----------------------------
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
echo "[3/4] instance running; waiting for status checks (~2-4 min)..."
aws ec2 wait instance-status-ok --instance-ids "$INSTANCE_ID"
EC2_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "      status OK; public IP: $EC2_IP"

# ---- 4. save state ----------------------------------------------------------
grep -v -e '^INSTANCE_ID=' -e '^EC2_IP=' "$STATE" > "$STATE.tmp" || true
mv "$STATE.tmp" "$STATE"
printf 'INSTANCE_ID=%s\nEC2_IP=%s\n' "$INSTANCE_ID" "$EC2_IP" >> "$STATE"
echo "[4/4] state updated"

cat <<DONE

============================================================
COMPUTE READY
INSTANCE_ID=$INSTANCE_ID
EC2_IP=$EC2_IP
KEY=$KEY_FILE
============================================================
DONE
