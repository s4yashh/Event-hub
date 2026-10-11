"""
EventHub worker — long-polls SQS and starts one Step Functions execution per
registration message.

Contract
  * Message body: {"eventId": "1", "userId": "5", "email": "a@b.c"}
  * Message is deleted ONLY after Step Functions StartExecution succeeds.
    If we crash, or the body is malformed, the message becomes visible again
    after the queue's visibility timeout and is finally moved to the DLQ
    after maxReceiveCount = 3 receives.
  * This worker does no business logic: all of it lives in the state machine
    (DynamoDB conditional write + SNS publish), which keeps the design simple
    and the workflow observable.
"""

import json
import logging
import time

import boto3
from botocore.exceptions import ClientError

REGION = "ap-south-1"
SSM_PREFIX = "/eventhub"

logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("eventhub-worker")

ssm = boto3.client("ssm", region_name=REGION)
sqs = boto3.client("sqs", region_name=REGION)
sfn = boto3.client("stepfunctions", region_name=REGION)

_param_cache: dict = {}


def param(name: str) -> str:
    if name not in _param_cache:
        resp = ssm.get_parameter(Name=f"{SSM_PREFIX}/{name}")
        _param_cache[name] = resp["Parameter"]["Value"]
    return _param_cache[name]


REQUIRED_FIELDS = ("eventId", "userId", "email")


