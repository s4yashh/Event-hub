# Phase 0 — FINAL STATUS (decided 11 Oct 2026)

## Decision

Build the event registration project in **account `061039790916`** (the account the CLI is signed
into). Project unchanged. Operating targets:

- **Aim for spend ≤ $1** by limiting live uptime and checking Billing frequently. The budget
  sends email alerts; AWS does not stop resources automatically at $1.
- **Window ≤ 48 h** total for live resources; EC2 is stopped between sessions.
- Budget notifications were configured at **$0.50 / $1.00** + forecasted 100%; verify
  recipients and current status in the Console before presenting.

The other account (`358148451349`) stays unused — no resources, $0.

## Done already (via AWS CLI, 11 Oct 2026)

- IAM bootstrap in `061039790916`:
  - Group `CloudProject-Admins` ← custom policy `CloudProject-Team-Policy`
    + AWS managed `SignInLocalDevelopmentAccess` (enables keyless `aws login` for users)
  - Users: `suyash`, `teammateb`, `teammatec` (temp password, must change at first login)
  - Roles: `CloudProject-EC2-Role` (+ profile `CloudProject-EC2-Profile`),
    `CloudProject-StepFunctions-Role`
- Budget `monthly-1usd`: notifications ACTUAL 50%, ACTUAL 100%, FORECASTED 100%

## To do — team (3 minutes each)

- [ ] Each user opens https://061039790916.signin.aws.amazon.com/console
- [ ] Signs in with username + temp password → sets a new password
- [ ] Tell the mentor → mentor switches this Mac's CLI from root to the IAM user via `aws login`
- [ ] Enable MFA for each team IAM user; no long-lived access keys are needed for supported CLI sign-in.
- [ ] Optional: send teammate emails to add to budget alerts

## Cost math (approximate, verify with Cost Explorer during the build)

| Item | Price (ap-south-1, approx) | 40 h |
|---|---|---|
| EC2 t3.micro | ~$0.0116/h | ~$0.46 |
| RDS db.t3.micro | ~$0.017/h | ~$0.68 |
| RDS storage 20 GB gp3 | ~$1.9/mo prorated | ~$0.10 |
| EBS 8 GB gp3 | ~$0.77/mo prorated | ~$0.04 |
| DynamoDB + SQS + SNS + SFN + CW | cents | ~$0.03 |
| **Combined (both running 40 h)** | | **~$1.3 → too high** |
| **Planned: RDS ~36 h + EC2 ~16–20 h, staggered** | | **~$0.85** ✅ |

These old estimates are planning notes, not current prices or a bill. Check the actual
charges in Billing → Bills and Cost Explorer, including taxes and other services.
during the window; stop EC2 whenever not actively testing/demoing.
