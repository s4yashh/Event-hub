# Cleanup Checklist — run AFTER evaluation, same day

Goal: every deletable resource gone and no new charges after cleanup. Check for
Elastic IPs, unattached volumes, snapshots, and stopped-instead-of-deleted instances.

Order matters (delete dependents before their parents). Tick as you go.

## 1. Stop the app
- [ ] On EC2: `sudo systemctl stop worker eventhub` (or just terminate in step 4).

## 2. CloudTrail + its bucket
- [ ] CloudTrail → Trails → `eventhub-trail` → **Stop logging** → **Delete**.
- [ ] S3 → bucket `eventhub-cloudtrail-<ACCOUNT_ID>` → empty → **Delete bucket** (untick
      "keep objects" confirmations carefully).

## 3. Monitoring
- [ ] CloudWatch → Alarms → delete `eventhub-cpu-high`, `eventhub-dlq-not-empty`,
      `eventhub-sfn-failed`.
- [ ] CloudWatch → Dashboards → delete `eventhub-dashboard`.

## 4. Compute (frees the EBS root volume)
- [ ] EC2 → Instances → select `eventhub-web` → **Instance state → Terminate instance**.
      → after it terminates, EC2 → **Volumes**: confirm the root volume disappeared
      (delete it manually if it shows "available").
- [ ] EC2 → **Snapshots**: delete any snapshots you created (none should exist if none were made).
- [ ] EC2 → **Elastic IPs**: confirm there are **zero** (we never allocated any — an unattached EIP
      is billed).
- [ ] Key pair `eventhub-key` may stay (free) or be deleted.

## 5. Database
- [ ] RDS → Databases → `eventhub-mysql` → delete:
  - **Uncheck** "Create final snapshot" (a final snapshot would be stored/billed).
  - Tick the acknowledgement box → Delete. (Takes a few minutes; status Deleting → gone.)
- [ ] RDS → **Snapshots** → confirm no manual/automated snapshots remain (delete any you find).
- [ ] RDS → Subnet groups → delete `eventhub-db-subnet-group` (only possible after the DB is gone).

## 6. Tables and messages
- [ ] DynamoDB → delete tables `EventSeats` and `Registrations`.
- [ ] SQS → delete `eventhub-registrations` and `eventhub-registrations-dlq`.
- [ ] SNS → delete topics `eventhub-notifications` and `eventhub-alerts`.
- [ ] Step Functions → delete state machine `eventhub-register`.
- [ ] Systems Manager → Parameter Store → delete all `/eventhub/*` parameters
      (db-host, db-user, db-name, db-password, flask-secret, queue-url, sns-topic-arn, alerts-topic-arn,
      state-machine-arn).

## 7. Network
- [ ] EC2/VPC → Security groups → delete `eventhub-web-sg` and `eventhub-db-sg`.
- [ ] VPC → Route tables → delete `eventhub-rt-public` and `eventhub-rt-private`
      (disassociate subnets first if prompted).
- [ ] VPC → Internet gateways → `eventhub-igw` → detach from VPC → delete.
- [ ] VPC → Subnets → delete the 3 `eventhub-*` subnets.
- [ ] VPC → Your VPCs → delete `eventhub-vpc` (must be last; takes a couple of minutes).

## 8. IAM (only after the team no longer needs console access)
- [ ] Each user deletes their own access key (IAM → their user → Security credentials).
- [ ] Root/IAM admin: delete users, group `CloudProject-Admins`,
      policies `CloudProject-Team-Policy`, `CloudProject-EC2-Policy`,
      `CloudProject-StepFunctions-Policy`, roles `CloudProject-EC2-Role`,
      `CloudProject-StepFunctions-Role`, instance profile `CloudProject-EC2-Profile`.
- [ ] Keep root MFA permanently (free, and it is your account's front door).

## 9. Budgets (keep until you are 100% done; they are free)
- [ ] After the final bill check (below), delete `zero-spend` and `monthly-1usd` if you are
      abandoning the account, or keep them at $0 cost as ongoing guardrails.

## 10. Verify cleanup and actual spend
- [ ] Billing → **Bills**: record the actual current-month total.
- [ ] Billing → **Cost Explorer**: verify no new usage after cleanup; prior charges can remain.
- [ ] Billing → **Free Tier**: no "at or above limit" services.
- [ ] Billing → **Credits**: nothing consumed unexpectedly.
- [ ] EC2 → Volumes/EIPs/Snapshots = empty. RDS → Databases/Snapshots = empty.
- [ ] One week later, re-check Bills once (charges can settle late).

## Do-not-forget notes
- **Stop ≠ delete.** A stopped EC2 still bills its EBS volume; a stopped RDS bills storage and
  **auto-restarts itself after 7 days**.
- Deleting RDS with backups disabled and no final snapshot is the zero-cost way out.
- If any resource refuses to delete, it is usually because a dependent still exists — work
  bottom-up through this list.
