#!/bin/bash
# EventHub bootstrap — run ON the EC2 instance after copying the app folder:
#   scp -i eventhub-key.pem -r app/ ec2-user@<EC2-public-IP>:~/eventhub-app
#   ssh -i eventhub-key.pem ec2-user@<EC2-public-IP>
#   sudo bash ~/eventhub-app/setup.sh
#
# What it does (idempotent — safe to re-run):
#   1. installs python + mysql client
#   2. copies the app to /opt/eventhub and builds a virtualenv
#   3. installs both systemd units and starts the web app
#      (the worker is started later, in Phase 5, once its queue and state
#       machine exist — it would just crash-loop before that)
set -euo pipefail

APP_SRC="$(cd "$(dirname "$0")" && pwd)"
APP_DIR=/opt/eventhub

