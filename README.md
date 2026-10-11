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

