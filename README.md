# EventHub — Event Registration & Ticketing System for College Clubs

**Course:** BCSE355L Cloud Architecture Design (VIT Vellore) · **Team:** three-person roles in `docs/team-work-division.pdf`
**Region:** ap-south-1 (Mumbai) · **Budget alert:** $1 (an alert, not a spending cap)

## Status

- **Verified 15 Oct 2026:** account `061039790916` in Mumbai; EC2 and RDS healthy; website
  returned HTTP 200; SQS, Step Functions, SNS, worker, CloudWatch, and CloudTrail setup
  completed. See `docs/console-walkthrough.md` for the exact evidence and open checks.
- **Next:** deploy the seat-count refresh with `bash scripts/04-deploy.sh`, verify a real
  booking and email, rehearse the Console walkthrough, then clean up billable resources
  after evaluation.

## The flow in one line

Browser → Flask app on EC2 → SQS (+DLQ) → Step Functions → DynamoDB conditional write
(atomic, no overbooking) → filtered SNS student email (CONFIRMED / WAITLISTED).
Users, clubs and events live in RDS MySQL; config + secrets in SSM Parameter Store;
CloudWatch alarms use a separate SNS topic; visibility comes from CloudWatch / CloudTrail / Budgets.

## Folder map

| Path | What it is |
|---|---|
| `docs/build-guide.md` | Phase-by-phase console + CLI steps (Phases 1–7). **Follow one phase at a time.** |
| `docs/architecture.md` | Diagram (Mermaid + ASCII) and component-by-component justification |
| `docs/aws-services.md` | Clear explanation of each AWS service, its role, and where it appears in the project |
| `docs/test-plan.md` | 20 test cases incl. seat-count refresh, last-seat race, waitlist, DLQ, alarms, CloudTrail |
| `docs/team-work-division.pdf` | Three-person responsibility and presentation plan (editable source: `docs/team-work-division.md`) |
| `docs/event-catalog.md` | Twelve events, dates, clubs, venues, and starting capacities |
| `docs/demo-script.md` | 8-minute demo script with speaking roles |
| `docs/console-walkthrough.md` | Every AWS Console page to show, expected proof, and live transaction trace |
| `docs/viva-qa.md` | Likely viva questions + model answers |
| `docs/timeline.md` | 4-week plan, tasks assigned to A/B/C, Week-1 daily checkpoints |
| `docs/cleanup-checklist.md` | Delete-everything checklist + verify no active billable resources |
| `docs/report.md` | Full report outline with draft text (incl. "Architecture at Scale" + Well-Architected review) |
| `docs/phase-0-checklist.md` | Phase 0 tracker (account, MFA, budgets) |
| `app/` | Flask app, reusable Jinja templates, responsive local CSS/JS, SQS worker, SQL schema/seed, systemd units, setup script |
| `aws/iam/` | Least-privilege policy JSON (team group, EC2 role, Step Functions role) |
| `aws/stepfunctions/` | State machine definition (Amazon States Language) |
| `aws/sns/` | Example SNS subscription filter policy |

## Rules we follow (from the project brief)

1. Keep cost low, check actual spend, and clean up promptly. A budget alert does not stop charges.
2. Syllabus services only — no Lambda/SES/ECS/EKS/API Gateway/Cognito/Amplify.
3. No NAT Gateway, ALB, Multi-AZ RDS, Aurora, read replicas, CloudFront or WAF in the built version
   (covered in the report's "Architecture at Scale" section only).
4. No hardcoded AWS keys — the app uses the EC2 instance role; people use IAM users with
   credentials in `~/.aws/credentials` (never in code, never in git).
5. Root is used only for account setup; daily work uses IAM users with MFA.

## Placeholders to replace while building

| Placeholder | Meaning |
|---|---|
| `<ACCOUNT_ID>` | 12-digit AWS account ID (top-right of console) |
| `<MY_IP>` | Your current IPv4 address (the console's "My IP" dropdown does this automatically) |
| Team emails | A, B, C emails used for SNS + budget alerts |

## Next step

Run `bash scripts/04-deploy.sh` from the project folder on the configured team Mac,
then test one confirmed booking and one waitlisted booking. Use
`docs/console-walkthrough.md` for the teacher's live AWS Console demonstration.
