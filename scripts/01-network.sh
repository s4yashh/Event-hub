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

# ---- 2. Subnets (first two available AZs) ----------------------------------
AZ1=$(aws ec2 describe-availability-zones \
  --query 'AvailabilityZones[?State==`available`].ZoneName' --output text | awk '{print $1}')
AZ2=$(aws ec2 describe-availability-zones \
  --query 'AvailabilityZones[?State==`available`].ZoneName' --output text | awk '{print $2}')
echo "      using AZs: $AZ1 + $AZ2"

mk_subnet() { # $1=Name tag  $2=CIDR  $3=AZ
  local sid
  sid=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=$1" "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[0].SubnetId' --output text)
  if [ "$sid" = "None" ]; then
    sid=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$2" \
      --availability-zone "$3" \
      --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$1}]" \
      --query 'Subnet.SubnetId' --output text)
  fi
  echo "$sid"
}
PUBLIC_SUBNET=$(mk_subnet eventhub-public-1a  10.0.1.0/24 "$AZ1")
PRIV1=$(mk_subnet         eventhub-private-1a 10.0.2.0/24 "$AZ1")
PRIV2=$(mk_subnet         eventhub-private-1b 10.0.3.0/24 "$AZ2")
aws ec2 modify-subnet-attribute --subnet-id "$PUBLIC_SUBNET" --map-public-ip-on-launch
echo "[2/7] subnets ready: public=$PUBLIC_SUBNET priv1=$PRIV1 priv2=$PRIV2"

# ---- 3. Internet gateway ---------------------------------------------------
IGW_ID=$(aws ec2 describe-internet-gateways --filters Name=tag:Name,Values=eventhub-igw \
  --query 'InternetGateways[0].InternetGatewayId' --output text)
if [ "$IGW_ID" = "None" ]; then
  IGW_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=eventhub-igw}]' \
    --query 'InternetGateway.InternetGatewayId' --output text)
  aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
  echo "[3/7] internet gateway created + attached ($IGW_ID)"
else
  echo "[3/7] internet gateway exists: $IGW_ID"
fi

# ---- 4. Route tables --------------------------------------------------------
RT_PUB=$(aws ec2 describe-route-tables \
  --filters Name=tag:Name,Values=eventhub-rt-public "Name=vpc-id,Values=$VPC_ID" \
  --query 'RouteTables[0].RouteTableId' --output text)
if [ "$RT_PUB" = "None" ]; then
  RT_PUB=$(aws ec2 create-route-table --vpc-id "$VPC_ID" \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=eventhub-rt-public}]' \
    --query 'RouteTable.RouteTableId' --output text)
  aws ec2 create-route --route-table-id "$RT_PUB" \
    --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" >/dev/null
fi
aws ec2 associate-route-table --route-table-id "$RT_PUB" \
  --subnet-id "$PUBLIC_SUBNET" >/dev/null || true

RT_PRIV=$(aws ec2 describe-route-tables \
  --filters Name=tag:Name,Values=eventhub-rt-private "Name=vpc-id,Values=$VPC_ID" \
  --query 'RouteTables[0].RouteTableId' --output text)
if [ "$RT_PRIV" = "None" ]; then
  RT_PRIV=$(aws ec2 create-route-table --vpc-id "$VPC_ID" \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=eventhub-rt-private}]' \
    --query 'RouteTable.RouteTableId' --output text)
fi
aws ec2 associate-route-table --route-table-id "$RT_PRIV" --subnet-id "$PRIV1" >/dev/null || true
aws ec2 associate-route-table --route-table-id "$RT_PRIV" --subnet-id "$PRIV2" >/dev/null || true
echo "[4/7] route tables ready (public has 0.0.0.0/0 -> igw; private has none)"

# ---- 5. Security groups -----------------------------------------------------
WEB_SG=$(aws ec2 describe-security-groups \
  --filters Name=group-name,Values=eventhub-web-sg "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[0].GroupId' --output text)
if [ "$WEB_SG" = "None" ]; then
  WEB_SG=$(aws ec2 create-security-group --group-name eventhub-web-sg \
    --description "EventHub web: HTTP from internet, SSH from team IP only" \
    --vpc-id "$VPC_ID" --query 'GroupId' --output text)
fi
MY_IP=$(curl -s https://checkip.amazonaws.com | tr -d '[:space:]')
# duplicates are ignored on re-run
aws ec2 authorize-security-group-ingress --group-id "$WEB_SG" \
  --protocol tcp --port 80 --cidr 0.0.0.0/0 2>/dev/null || true
aws ec2 authorize-security-group-ingress --group-id "$WEB_SG" \
  --protocol tcp --port 22 --cidr "$MY_IP/32" 2>/dev/null || true

DB_SG=$(aws ec2 describe-security-groups \
  --filters Name=group-name,Values=eventhub-db-sg "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[0].GroupId' --output text)
if [ "$DB_SG" = "None" ]; then
  DB_SG=$(aws ec2 create-security-group --group-name eventhub-db-sg \
    --description "EventHub DB: MySQL only from the web security group" \
    --vpc-id "$VPC_ID" --query 'GroupId' --output text)
fi
aws ec2 authorize-security-group-ingress --group-id "$DB_SG" \
  --protocol tcp --port 3306 --source-group "$WEB_SG" 2>/dev/null || true
echo "[5/7] security groups ready (SSH allowed from $MY_IP/32 only)"

# ---- 6. RDS DB subnet group --------------------------------------------------
if aws rds describe-db-subnet-groups --db-subnet-group-name eventhub-db-subnet-group >/dev/null 2>&1; then
  echo "[6/7] DB subnet group exists"
else
  aws rds create-db-subnet-group \
    --db-subnet-group-name eventhub-db-subnet-group \
    --db-subnet-group-description "EventHub private subnets (2 AZs, required by RDS)" \
    --subnet-ids "$PRIV1" "$PRIV2" >/dev/null
  echo "[6/7] DB subnet group created"
fi

# ---- 7. Save state ----------------------------------------------------------
cat > "$STATE" <<EOF
ACCOUNT_ID=$ACCOUNT_ID
REGION=$REGION
VPC_ID=$VPC_ID
AZ1=$AZ1
AZ2=$AZ2
PUBLIC_SUBNET=$PUBLIC_SUBNET
PRIV1=$PRIV1
PRIV2=$PRIV2
IGW_ID=$IGW_ID
RT_PUB=$RT_PUB
RT_PRIV=$RT_PRIV
WEB_SG=$WEB_SG
DB_SG=$DB_SG
EOF
echo "[7/7] state saved to scripts/state.env"

cat <<DONE

============================================================
NETWORK BUILD COMPLETE — copy this block back to your mentor:

VPC_ID=$VPC_ID
PUBLIC_SUBNET=$PUBLIC_SUBNET
PRIV1=$PRIV1   PRIV2=$PRIV2   (AZs: $AZ1, $AZ2)
WEB_SG=$WEB_SG
DB_SG=$DB_SG
============================================================
DONE
