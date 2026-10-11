"""EventHub Flask app. AWS behavior is preserved; templates provide the UI."""

import json
from functools import wraps

import boto3
import pymysql
from flask import Flask, flash, redirect, render_template, request, session, url_for
from werkzeug.security import check_password_hash, generate_password_hash

REGION = "ap-south-1"
SSM_PREFIX = "/eventhub"
SEATS_TABLE = "EventSeats"
REGISTRATIONS_TABLE = "Registrations"

app = Flask(__name__)
ssm = boto3.client("ssm", region_name=REGION)
sqs = boto3.client("sqs", region_name=REGION)
sns = boto3.client("sns", region_name=REGION)
ddb = boto3.resource("dynamodb", region_name=REGION)
_param_cache = {}


def param(name: str, decrypt: bool = False) -> str:
    """Read and cache a Systems Manager Parameter Store value."""
    key = (name, decrypt)
    if key not in _param_cache:
        response = ssm.get_parameter(
            Name=f"{SSM_PREFIX}/{name}", WithDecryption=decrypt
        )
        _param_cache[key] = response["Parameter"]["Value"]
    return _param_cache[key]


app.secret_key = param("flask-secret", decrypt=True)


def db():
    """Open a MySQL connection to the private RDS instance."""
    return pymysql.connect(
        host=param("db-host"),
        user=param("db-user"),
        password=param("db-password", decrypt=True),
        database=param("db-name"),
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=True,
    )


def login_required(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        if not session.get("user_id"):
            return redirect(url_for("login"))
        return fn(*args, **kwargs)
    return wrapper


def ensure_notification_subscription(email: str) -> None:
    """Subscribe the student's address with an email filter so they receive
    only their own notifications. Best effort: never blocks registration.

    SNS delivers only to confirmed subscribers, so a new student receives a
    one-time AWS confirmation email; after confirming, status updates reach
    them. The workflow publishes an `email` message attribute that the
    filter policy matches against.
    """
    try:
        sns.subscribe(
            TopicArn=param("sns-topic-arn"),
            Protocol="email",
            Endpoint=email,
            Attributes={"FilterPolicy": json.dumps({"email": [email]})},
        )
        app.logger.info("notification subscription requested for %s", email)
    except Exception:
        app.logger.warning(
            "notification subscription failed for %s", email, exc_info=True
        )

