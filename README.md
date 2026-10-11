# EventHub — Event Registration & Ticketing System for College Clubs

**Course:** BCSE355L Cloud Architecture Design (VIT Vellore) · **Team:** Person A (infra/security) · Person B (data/app) · Person C (integration/ops)
**Region:** ap-south-1 (Mumbai) · **Budget:** $0 (hard rule)

## Status

- **Build target (decided 11 Oct 2026):** account `<ACCOUNT_ID>` — no free tier — with a hard
  spend cap of **$1** and ≤48 h of live resources (we plan ~36–40 h combined; see
  `docs/phase-0-checklist.md` for the cost plan). Budget `monthly-1usd` alerts at 50% / 100%.
- **Done:** IAM bootstrap (group + 3 users + both service roles + keyless `aws login` policy)
  and the $1 budget, created via AWS CLI on 11 Oct 2026. New account `<SECOND_ACCOUNT_ID>` stays
  unused ($0).
- **Next:** each user's first console login (change temp password) → switch the CLI to the IAM
  user → build Phases 2–6 (network → data → compute → deploy → integration → monitoring) →
  test → demo → delete everything (cleanup checklist).
- Everything that does **not** need an AWS account is prepared in this repo (code, policies,
  guides, report).

## The flow in one line

Browser → Flask app on EC2 → SQS (+DLQ) → Step Functions → DynamoDB conditional write
(atomic, no overbooking) → SNS email (CONFIRMED / WAITLISTED).
Users, clubs and events live in RDS MySQL; config + secrets in SSM Parameter Store;
visibility via CloudWatch / CloudTrail / Budgets.

## Folder map

| Path | What it is |
|---|---|
| `docs/build-guide.md` | Phase-by-phase console + CLI steps (Phases 1–7). **Follow one phase at a time.** |
| `docs/architecture.md` | Diagram (Mermaid + ASCII) and component-by-component justification |
| `docs/test-plan.md` | 12 test cases incl. last-seat race, waitlist, DLQ, alarms, CloudTrail |
| `docs/demo-script.md` | 8-minute demo script with speaking roles |
| `docs/viva-qa.md` | Likely viva questions + model answers |
| `docs/timeline.md` | 4-week plan, tasks assigned to A/B/C, Week-1 daily checkpoints |
| `docs/cleanup-checklist.md` | Delete-everything checklist + verify $0 |
| `docs/report.md` | Full report outline with draft text (incl. "Architecture at Scale" + Well-Architected review) |
| `docs/phase-0-checklist.md` | Phase 0 tracker (account, MFA, budgets) |
| `app/` | Flask app, reusable Jinja templates, responsive local CSS/JS, SQS worker, SQL schema/seed, systemd units, setup script |
| `aws/iam/` | Least-privilege policy JSON (team group, EC2 role, Step Functions role) |
| `aws/stepfunctions/` | State machine definition (Amazon States Language) |
| `aws/sns/` | Example SNS subscription filter policy |

