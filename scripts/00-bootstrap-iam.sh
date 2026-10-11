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

# ---- 1. Team policy + group -------------------------------------------------
cat > /tmp/team-policy.json <<'POLICY'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ProjectServices",
      "Effect": "Allow",
      "Action": [
        "ec2:*", "rds:*", "dynamodb:*", "sqs:*", "sns:*", "states:*",
        "s3:*", "cloudwatch:*", "logs:*", "cloudtrail:*", "ssm:*",
        "tag:GetResources", "ce:GetCostAndUsage", "ce:Get*",
        "budgets:ViewBudget", "budgets:Describe*",
        "sts:GetCallerIdentity", "sts:GetSessionToken"
      ],
      "Resource": "*"
    },
    {
      "Sid": "KMSReadOnly",
      "Effect": "Allow",
      "Action": [
        "kms:DescribeKey", "kms:ListKeys", "kms:ListAliases",
        "kms:GetKeyPolicy", "kms:GetKeyRotationStatus"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ListIAMReadOnly",
      "Effect": "Allow",
      "Action": [
        "iam:ListUsers", "iam:ListGroups", "iam:ListRoles", "iam:ListPolicies",
        "iam:ListInstanceProfiles", "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole",
        "iam:GetRole", "iam:GetInstanceProfile"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ManageOnlyProjectRolesAndPolicies",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole", "iam:DeleteRole", "iam:TagRole", "iam:UntagRole",
        "iam:AttachRolePolicy", "iam:DetachRolePolicy",
        "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
        "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile",
        "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
        "iam:CreatePolicy", "iam:DeletePolicy", "iam:CreatePolicyVersion",
        "iam:SetDefaultPolicyVersion", "iam:TagPolicy", "iam:UntagPolicy"
      ],
      "Resource": [
        "arn:aws:iam::061039790916:role/CloudProject-*",
        "arn:aws:iam::061039790916:instance-profile/CloudProject-*",
        "arn:aws:iam::061039790916:policy/CloudProject-*"
      ]
    },
    {
      "Sid": "PassProjectRolesToServicesOnly",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::061039790916:role/CloudProject-*",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": ["ec2.amazonaws.com", "states.amazonaws.com"]
        }
      }
    },
    {
      "Sid": "SelfServiceCredentialsAndMFA",
      "Effect": "Allow",
      "Action": [
        "iam:GetUser", "iam:GetLoginProfile", "iam:ChangePassword",
        "iam:CreateAccessKey", "iam:DeleteAccessKey", "iam:ListAccessKeys",
        "iam:UpdateAccessKey", "iam:ListMFADevices", "iam:EnableMFADevice",
        "iam:ResyncMFADevice", "iam:DeactivateMFADevice", "iam:DeleteVirtualMFADevice"
      ],
      "Resource": [
        "arn:aws:iam::061039790916:user/${aws:username}",
        "arn:aws:iam::061039790916:mfa/${aws:username}"
      ]
    },
    {
      "Sid": "IdentitiesAreRootManaged",
      "Effect": "Deny",
      "Action": [
        "iam:CreateUser", "iam:DeleteUser", "iam:CreateLoginProfile",
        "iam:UpdateLoginProfile", "iam:DeleteLoginProfile", "iam:CreateGroup",
        "iam:DeleteGroup", "iam:AddUserToGroup", "iam:RemoveUserFromGroup",
        "iam:AttachGroupPolicy", "iam:DetachGroupPolicy", "iam:PutGroupPolicy",
        "iam:DeleteGroupPolicy"
      ],
      "Resource": "*"
    },
    {
      "Sid": "NoOutOfSyllabusOrBillingServices",
      "Effect": "Deny",
      "Action": [
        "lambda:*", "ses:*", "ecs:*", "eks:*", "apigateway:*",
        "cognito-idp:*", "cognito-identity:*", "amplify:*",
        "account:*", "organizations:*", "support:*", "aws-marketplace:*",
        "route53domains:*", "savingsplans:*", "kms:CreateKey", "kms:CreateAlias"
      ],
      "Resource": "*"
    }
  ]
}
POLICY

aws iam create-policy --policy-name CloudProject-Team-Policy \
  --policy-document file:///tmp/team-policy.json >/dev/null
aws iam create-group --group-name "$GROUP" >/dev/null
aws iam attach-group-policy --group-name "$GROUP" \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/CloudProject-Team-Policy"
echo "[1/4] team policy + group created"

# ---- 2. Users ---------------------------------------------------------------
for u in "${USERS[@]}"; do
  aws iam create-user --user-name "$u" >/dev/null
  aws iam add-user-to-group --group-name "$GROUP" --user-name "$u"
  aws iam create-login-profile --user-name "$u" \
    --password "$TEMP_PASSWORD" --password-reset-required
  echo "      user $u created (console access)"
done
echo "[2/4] users created"

# ---- 3. EC2 role + instance profile ----------------------------------------
cat > /tmp/ec2-trust.json <<'TRUST'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
TRUST

cat > /tmp/ec2-policy.json <<'POLICY'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadSeatCountsForEventList",
      "Effect": "Allow",
      "Action": "dynamodb:GetItem",
      "Resource": "arn:aws:dynamodb:ap-south-1:061039790916:table/EventSeats"
    },
    {
      "Sid": "ReadOwnRegistrations",
      "Effect": "Allow",
      "Action": ["dynamodb:GetItem", "dynamodb:Scan"],
      "Resource": "arn:aws:dynamodb:ap-south-1:061039790916:table/Registrations"
    },
    {
      "Sid": "WebAppSendsRegistrationIntents",
      "Effect": "Allow",
      "Action": "sqs:SendMessage",
      "Resource": "arn:aws:sqs:ap-south-1:061039790916:eventhub-registrations"
    },
    {
      "Sid": "WorkerConsumesRegistrationQueue",
      "Effect": "Allow",
      "Action": ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility"],
      "Resource": "arn:aws:sqs:ap-south-1:061039790916:eventhub-registrations"
    },
    {
      "Sid": "WorkerStartsRegistrationWorkflow",
      "Effect": "Allow",
      "Action": "states:StartExecution",
      "Resource": "arn:aws:states:ap-south-1:061039790916:stateMachine:eventhub-register"
    },
    {
      "Sid": "ReadConfigurationParameters",
      "Effect": "Allow",
      "Action": "ssm:GetParameter",
      "Resource": "arn:aws:ssm:ap-south-1:061039790916:parameter/eventhub/*"
    },
    {
      "Sid": "DecryptSecureStringsOnlyViaSSM",
      "Effect": "Allow",
      "Action": "kms:Decrypt",
      "Resource": "*",
      "Condition": {
        "StringEquals": { "kms:ViaService": "ssm.ap-south-1.amazonaws.com" }
      }
    },
    {
      "Sid": "SubscribeStudentsForNotifications",
      "Effect": "Allow",
      "Action": [
        "sns:Subscribe",
        "sns:SetSubscriptionAttributes"
      ],
      "Resource": "arn:aws:sns:ap-south-1:061039790916:eventhub-notifications"
    }
  ]
}
POLICY

aws iam create-role --role-name CloudProject-EC2-Role \
  --assume-role-policy-document file:///tmp/ec2-trust.json >/dev/null
aws iam put-role-policy --role-name CloudProject-EC2-Role \
  --policy-name CloudProject-EC2-Policy \
  --policy-document file:///tmp/ec2-policy.json
aws iam create-instance-profile --instance-profile-name CloudProject-EC2-Profile >/dev/null
aws iam add-role-to-instance-profile \
  --instance-profile-name CloudProject-EC2-Profile \
  --role-name CloudProject-EC2-Role
echo "[3/4] EC2 role + instance profile created"

# ---- 4. Step Functions role -------------------------------------------------
cat > /tmp/sfn-trust.json <<'TRUST'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "states.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
TRUST

cat > /tmp/sfn-policy.json <<'POLICY'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReserveSeatWithConditionalUpdate",
      "Effect": "Allow",
      "Action": "dynamodb:UpdateItem",
      "Resource": "arn:aws:dynamodb:ap-south-1:061039790916:table/EventSeats"
    },
    {
      "Sid": "WriteRegistrationResult",
      "Effect": "Allow",
      "Action": "dynamodb:PutItem",
      "Resource": "arn:aws:dynamodb:ap-south-1:061039790916:table/Registrations"
    },
    {
      "Sid": "PublishNotification",
      "Effect": "Allow",
      "Action": "sns:Publish",
      "Resource": "arn:aws:sns:ap-south-1:061039790916:eventhub-notifications"
    }
  ]
}
POLICY

aws iam create-role --role-name CloudProject-StepFunctions-Role \
  --assume-role-policy-document file:///tmp/sfn-trust.json >/dev/null
aws iam put-role-policy --role-name CloudProject-StepFunctions-Role \
  --policy-name CloudProject-StepFunctions-Policy \
  --policy-document file:///tmp/sfn-policy.json
echo "[4/4] Step Functions role created"

cat <<DONE

================================================================
BOOTSTRAP COMPLETE — copy this whole block back to your mentor:

ACCOUNT_ID=$ACCOUNT_ID
USERS=${USERS[*]}
TEMP_PASSWORD=$TEMP_PASSWORD
Sign-in URL: https://${ACCOUNT_ID}.signin.aws.amazon.com/console
Roles: CloudProject-EC2-Role (+ profile CloudProject-EC2-Profile)
       CloudProject-StepFunctions-Role
================================================================

NEXT STEPS FOR EACH TEAM MEMBER (do today, takes 3 min each):
  1. Open  https://${ACCOUNT_ID}.signin.aws.amazon.com/console
  2. Sign in: IAM username = your name, password = $TEMP_PASSWORD
  3. When asked, set your own new password
  4. IAM -> Users -> (yourself) -> Security credentials -> Create access key
     -> "Command Line Interface (CLI)" -> copy both values (save them once!)
  5. On your Mac:
       aws configure          # paste key + secret, region ap-south-1, output json
       aws sts get-caller-identity   # must show YOUR user, not root
DONE
