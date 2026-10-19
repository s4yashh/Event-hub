# 4-Week Plan — EventHub (BCSE355L)

Owners: **A** infra/security · **B** data/application · **C** integration/ops.
Everyone must be able to explain the full flow in the viva — pair up when someone is blocked.

> Slot in the Week-0 decision: **which AWS account we build in** (pending). Once the account
> exists, Phase 0 setup (MFA, region, budgets) is ~20 minutes on the new account.

## Week 1 — Foundations (account → VPC → data stores)

Daily checkpoints (15 min stand-up each day):

| Day | A | B | C | Checkpoint (all) |
|---|---|---|---|---|
| Mon | Phase 0 on chosen account: root MFA, region ap-south-1, budgets | Read schema.sql + seed.sql; prepare demo emails | Read SQS/SNS/SFN sections of build guide; create team email list | Confirm budgets visible, region set |
| Tue | Phase 1: group + 3 IAM users + MFA per user; EC2 role; SFN role | Verify policy JSON placeholders replaced; test `aws sts get-caller-identity` per user | Verify SFN role policy; draft DLQ naming | All three log in with own IAM user |
| Wed | Phase 2: VPC, subnets, IGW, route tables, SGs, DB subnet group | Prepare SQL files for import | Confirm security-group rules match plan | VPC diagram matches actual resources |
| Thu | Phase 3: launch RDS (wait ~10 min) | Phase 3: create DynamoDB tables + seed EventSeats | Phase 3: create SSM parameters (db-user/name/password now; host after RDS) | RDS status "Available"; DDB items visible |
| Fri | Phase 4: launch EC2, key pair, security group, role | Phase 4: scp app, run setup.sh, load schema + seed | Phase 4: verify web app reachable on port 80 | /events page shows 3 events + seats |

## Week 2 — Integration (queue → workflow → notifications)

| A | B | C |
|---|---|---|
| Wire IAM role permissions if AccessDenied appears (most common bug) | Add register button flows; test signup/login edge cases | Phase 5: SQS + DLQ, SNS topic + subscriptions, Step Functions from ASL, SSM queue/SFN params, start worker |
| Review state machine definition with B | Test StartExecution manually with sample input | Test poison message → DLQ path |
| - | - | **Checkpoint Fri: full flow works end to end (register → email)** |

## Week 3 — Observability + hardening

| A | B | C |
|---|---|---|
| SSH/SSM access checks; EBS encryption verify; re-check no keys on disk | Fill test-plan T01–T07 results; fix UI bugs | Phase 6: CloudWatch dashboard + 3 alarms, CloudTrail trail + S3 lifecycle rule |
| Re-run race test with 3 parallel executions | Document results with screenshots | Run T08–T14 (DLQ, alarms, CloudTrail lookup) |
| - | Report: architecture + testing sections | Report: monitoring section |

## Week 4 — Report, demo, evaluation, cleanup

| A | B | C |
|---|---|---|
| Finalize architecture diagram + security section | Finalize application + results sections | Finalize monitoring + cost sections |
| Dry-run demo twice with the whole team | Prepare seed/reset script for demo day (reset seats to 2/50/0) | Rehearse alarm emails |
| **After evaluation only:** cleanup checklist | Confirm Cost Explorer shows $0 | Verify budgets + bills; delete budgets at the very end |

## Rules of engagement

- One phase at a time; never continue past a failing checkpoint — paste the error instead.
- Every resource name follows the `eventhub-*` / `CloudProject-*` prefix so cleanup is mechanical.
- Screenshot everything you build (console pages) — free evidence for the report.
- Never commit `.pem` files, access keys, or the EC2 public IP of a running instance to git.
