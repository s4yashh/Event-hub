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


