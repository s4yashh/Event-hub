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

