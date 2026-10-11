#!/usr/bin/env bash
# =============================================================================
# EventHub build — STEP 6: monitoring (CloudWatch alarms + dashboard, CloudTrail)
# Run: bash scripts/06-monitoring.sh
# =============================================================================
set -euo pipefail

REGION="${REGION:-ap-south-1}"
export AWS_DEFAULT_REGION="$REGION"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="$SCRIPT_DIR/state.env"
# shellcheck disable=SC1090
source "$STATE"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
TOPIC_ARN=$(aws ssm get-parameter --name /eventhub/sns-topic-arn --query Parameter.Value --output text)
SM_ARN=$(aws ssm get-parameter --name /eventhub/state-machine-arn --query Parameter.Value --output text)

echo "== EventHub monitoring build =="

# ---- 1. Alarms --------------------------------------------------------------
aws cloudwatch put-metric-alarm --alarm-name eventhub-cpu-high \
  --namespace AWS/EC2 --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
  --statistic Average --period 300 --evaluation-periods 1 \
  --threshold 70 --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching \
  --alarm-actions "$TOPIC_ARN"
echo "[1/3] alarm eventhub-cpu-high (EC2 CPU > 70%)"

aws cloudwatch put-metric-alarm --alarm-name eventhub-dlq-not-empty \
  --namespace AWS/SQS --metric-name ApproximateNumberOfMessagesVisible \
  --dimensions Name=QueueName,Value=eventhub-registrations-dlq \
  --statistic Maximum --period 60 --evaluation-periods 1 \
  --threshold 0 --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching \
  --alarm-actions "$TOPIC_ARN"
echo "      alarm eventhub-dlq-not-empty (period 60s for a snappy demo)"

aws cloudwatch put-metric-alarm --alarm-name eventhub-sfn-failed \
  --namespace AWS/States --metric-name ExecutionsFailed \
  --dimensions Name=StateMachineArn,Value="$SM_ARN" \
  --statistic Sum --period 300 --evaluation-periods 1 \
  --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold \
  --treat-missing-data notBreaching \
  --alarm-actions "$TOPIC_ARN"
echo "      alarm eventhub-sfn-failed (any failed execution)"

# ---- 2. Dashboard -----------------------------------------------------------
cat > /tmp/dashboard.json <<EOF
{
  "widgets": [
    {"type":"metric","x":0,"y":0,"width":12,"height":6,"properties":{
      "title":"SQS backlog (main + DLQ)","region":"ap-south-1","stat":"Maximum","period":300,
      "metrics":[
        ["AWS/SQS","ApproximateNumberOfMessagesVisible","QueueName","eventhub-registrations"],
        [".","ApproximateNumberOfMessagesVisible","QueueName","eventhub-registrations-dlq"]]}},
    {"type":"metric","x":12,"y":0,"width":12,"height":6,"properties":{
      "title":"Step Functions executions","region":"ap-south-1","stat":"Sum","period":300,
      "metrics":[
        ["AWS/States","ExecutionsSucceeded","StateMachineArn","$SM_ARN"],
        [".","ExecutionsFailed","StateMachineArn","$SM_ARN"]]}},
    {"type":"metric","x":0,"y":6,"width":12,"height":6,"properties":{
      "title":"EC2 CPU %","region":"ap-south-1","stat":"Average","period":300,
      "metrics":[["AWS/EC2","CPUUtilization","InstanceId","$INSTANCE_ID"]]}},
    {"type":"metric","x":12,"y":6,"width":12,"height":6,"properties":{
      "title":"Seat-race losers (DynamoDB conditional check failures)","region":"ap-south-1","stat":"Sum","period":300,
      "metrics":[["AWS/DynamoDB","ConditionalCheckFailedRequests","TableName","EventSeats"]]}}
  ]
}
EOF
aws cloudwatch put-dashboard --dashboard-name eventhub-dashboard \
  --dashboard-body file:///tmp/dashboard.json >/dev/null
echo "[2/3] dashboard eventhub-dashboard (4 widgets)"

