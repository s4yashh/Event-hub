# Scripted CLI build (alternative to console clicking)

One bash script per phase. Run them **in order**, from this project folder.
Each script is safe to re-run (checks before creating) and prints a summary block
at the end — **copy that block back to your mentor each time**.

| Order | Script | Where you run it | Creates |
|---|---|---|---|
| 0 | `00-bootstrap-iam.sh` | **AWS CloudShell, signed in as ROOT** | team group + policy, 3 IAM users, EC2 role + instance profile, Step Functions role |
| 1 | `01-network.sh` | your Mac (AWS CLI configured) | VPC, 1 public + 2 private subnets, IGW, route tables, security groups, RDS DB subnet group |
| 2 | `02-data.sh` | your Mac | SSM parameters, DynamoDB tables + seed, RDS MySQL (~10 min wait) |
| 3 | `03-compute.sh` | your Mac | key pair, EC2 instance (waits for it to boot) |
| 4 | `04-deploy.sh` | your Mac | app upload (scp), DB schema load, start web app, verify |
| 5 | `05-integration.sh` | your Mac | SQS + DLQ, separate SNS ticket and alarm topics, Step Functions state machine, start worker, smoke test |
| 6 | `06-monitoring.sh` | your Mac | 3 CloudWatch alarms, CloudTrail trail + bucket + lifecycle rule |
| 9 | `99-cleanup.sh` | your Mac | deletes everything (run only after evaluation!) |

The phase scripts are present. Inspect the chosen AWS account and edit team-specific
settings before running them. For integration, set `DEMO_EMAILS` to space-separated
inboxes that will receive SNS confirmation links, for example
`DEMO_EMAILS='first@example.com second@example.com' bash scripts/05-integration.sh`.
These addresses receive operator alarms. Students confirm their own filtered ticket
subscriptions through the app. The integration script adds an email filter to each
existing confirmed ticket subscription. Review any pending or non-email subscriptions
it reports, and allow 15 minutes before the live email demo.

After changing the email code on an existing EC2 deployment, run `04-deploy.sh`
to upload the new app and worker, then `05-integration.sh` to update the state
machine/topics, then `06-monitoring.sh` to point alarms at `eventhub-alerts`.

## Ground rules

- Scripts never contain access keys. They use the credentials you set with
  `aws configure` (~/.aws/credentials) or CloudShell's temporary credentials.
- `scripts/state.env` stores the resource IDs created along the way so later scripts
  can find them. Do not delete it mid-build (it is in .gitignore).
- If a script errors: **do not rerun it blindly**. Copy the last ~20 lines of output
  and send them to your mentor.
- Phase 1 note: script 00 runs inside **CloudShell as root**, which is how we create the
  first identities without ever creating root access keys (hard rule).

## If you already started Phase 1 in the console

Tell your mentor before running `00-bootstrap-iam.sh` — the script stops cleanly if the
group already exists, but we may need to reconcile a few resources by hand.
