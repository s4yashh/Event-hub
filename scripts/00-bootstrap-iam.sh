#!/usr/bin/env bash
# =============================================================================
# EventHub build — STEP 0: IAM bootstrap (group, users, roles)
#
# RUN THIS IN AWS CLOUDSHELL WHILE SIGNED IN AS ROOT:
#   Console top bar -> CloudShell icon ( >_ ) -> paste this whole file -> Enter
#   (If pasting multi-line text is messy: in CloudShell use
#    Actions -> Upload file, then run:  bash 00-bootstrap-iam.sh )
#
# Why CloudShell as root: only root may create the first IAM identities, and we
# must NOT create root access keys (hard rule). CloudShell uses temporary
# credentials, so nothing persistent is stored anywhere.
#
# Creates:
#   1. Managed policy CloudProject-Team-Policy + group CloudProject-Admins
#   2. The three IAM users (console access, temp password, change at first login)
#   3. CloudProject-EC2-Role + instance profile CloudProject-EC2-Profile
#   4. CloudProject-StepFunctions-Role
#
# Creates NO access keys and stores NO secrets in this file.
# =============================================================================
set -euo pipefail

# ---- EDIT THESE TWO LINES IF NEEDED -----------------------------------------
USERS=(suyash teammateb teammatec)      # three usernames (lowercase, no spaces)
TEMP_PASSWORD='CHANGE_ME_BEFORE_USE'    # set a strong temp password; each user changes it at first login
# -----------------------------------------------------------------------------

REGION="ap-south-1"
GROUP="CloudProject-Admins"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "== EventHub IAM bootstrap =="
echo "Account : $ACCOUNT_ID"
echo "Region  : $REGION"
echo

if aws iam get-group --group-name "$GROUP" >/dev/null 2>&1; then
  echo "Group $GROUP already exists -> bootstrap already ran. Nothing to do."
  exit 0
fi

