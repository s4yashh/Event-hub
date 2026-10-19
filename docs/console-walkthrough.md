# AWS Console walkthrough for the assessment

Use **Asia Pacific (Mumbai), `ap-south-1`** for regional services. IAM, Budgets, and Billing are global. Sign in with a team IAM user, then show the running app first and trace one registration through the services. Keep this page beside the Console during the assessment.

## Verified on 15 October 2026

- Console screenshots: `eventhub-web` was Running with 3/3 checks passed; `eventhub-mysql` was Available in account `061039790916`.
- Deployment output: the app loaded three events from MySQL and `http://13.235.245.147/` returned HTTP 200.
- Integration output: the SQS queue and DLQ, both SNS topics, the `eventhub-register` state machine, and the worker were running; the scripted registration smoke test completed.
- Monitoring output: the three CloudWatch alarms were `OK`, the dashboard was created, and CloudTrail reported `IsLogging=True`.
- Still to verify with a real inbox: a confirmed student SNS subscription, a filtered ticket email, and an operator alarm email.
- The booking page's automatic seat-count refresh and nine extra events were added after this verification. Redeploy with `bash scripts/04-deploy.sh`, then check twelve event cards and run T15/T16 in `docs/test-plan.md` before presenting them as live.

## Before the teacher arrives

1. Confirm the account and region in the Console. Run `aws sts get-caller-identity` locally if CLI sign-in works; the account must match the resources you intend to show.
2. Check **EC2 → Instances → `eventhub-web`** is running and copy its public IP. Open `http://<public-ip>/`. Use only disposable demo passwords: this lab serves plain HTTP.
3. Confirm **RDS → Databases → `eventhub-mysql`** is Available, **Step Functions → `eventhub-register`** exists, and both SQS queues exist.
4. On EC2, run `sudo systemctl is-active eventhub worker`. If either is not active, inspect `journalctl -u eventhub -n 50` or `journalctl -u worker -n 50`.
5. Run `bash scripts/demo-reset.sh` only when no registration is in flight. This removes old demo tickets and restores all twelve starting capacities (the core three return to **2 / 50 / 0**). Prepare three distinct demo accounts for the capacity race.
6. For each demo user, select **Email me ticket updates** during sign-up (or use **Request email updates** on My tickets), then confirm the AWS email. In **SNS → Topics**, verify `eventhub-notifications` has only filtered student subscriptions and `eventhub-alerts` has the team alarm subscriptions. All demo subscriptions must say **Confirmed**. Prepare them at least 15 minutes before the first live registration so the filter policies can propagate.
7. Open the Console pages below in tabs. Capture screenshots as you go; each screenshot should show the resource name and relevant configuration, with passwords and personal addresses hidden.

## Show every service in the architecture

| Order | Console page | Show the teacher | Why it is used |
|---|---|---|---|
| 1 | **VPC → Your VPCs → `eventhub-vpc`**, then **Subnets**, **Route tables**, **Internet gateways**, **Security groups** | One public subnet for EC2, two private subnets for RDS, public route to the internet gateway, database port 3306 allowed from the web security group | Network isolation and restricted database access |
| 2 | **EC2 → Instances → `eventhub-web`**, then **Storage → Volumes** | Running `t3.micro`, public IP, attached `CloudProject-EC2-Profile`, encrypted root EBS volume | Hosts the Flask web app and SQS worker |
| 3 | **IAM → Roles**, **User groups**, **Users** | `CloudProject-EC2-Role`, `CloudProject-StepFunctions-Role`, and team group; show role permissions without revealing credentials | Service identities and scoped permissions |
| 4 | **Systems Manager → Parameter Store → `/eventhub/`** | Parameter names and types, including `db-password` and `flask-secret` as SecureString; do not click **Show value** | App configuration and secrets |
| 5 | **RDS → Databases → `eventhub-mysql`**, then **Subnet groups** | MySQL, private access, security group, two-AZ subnet group | Stores users, clubs, and event descriptions |
| 6 | **DynamoDB → Tables → `EventSeats` and `Registrations` → Explore table items** | Seat count before and after registering; one ticket per event and user | Conditional seat reservation and ticket status |
| 7 | **SQS → Queues → `eventhub-registrations` → Dead-letter queue** | Main queue, `eventhub-registrations-dlq`, redrive after 3 receives, queue depth | Buffers requests and preserves poison messages |
| 8 | **Step Functions → State machines → `eventhub-register` → Executions** | Open a confirmed execution and a waitlisted execution; show the conditional update and branch in graph/history | Visible, auditable registration workflow |
| 9 | **SNS → Topics → `eventhub-notifications` and `eventhub-alerts` → Subscriptions** | Filtered student subscriptions on the ticket topic, team inboxes on the alarm topic, and a readable ticket email | Keeps personal ticket updates separate from operator alerts |
| 10 | **CloudWatch → Dashboards → `eventhub-dashboard`**, then **Alarms** | SQS depth, workflow outcomes, EC2 CPU, conditional check failures; DLQ alarm | Monitoring and failure alerts |
| 11 | **CloudTrail → Trails → `eventhub-trail`**, then **Event history** | Logging status and a management event such as `RunInstances` or `CreateDBInstance` | Records who changed AWS resources |
| 12 | **S3 → Buckets → `eventhub-cloudtrail-<account-id>`** | CloudTrail log destination and 30-day lifecycle policy | Stores audit logs |
| 13 | **KMS → AWS managed keys** | `aws/ebs`, `aws/rds`, `aws/ssm` if visible in the account | Encryption at rest for the built resources |
| 14 | **Billing and Cost Management → Budgets → `monthly-1usd`** | Alert thresholds and current actual spend | Cost visibility; alerts do not impose a spending cap |

Only claim a service is **deployed** after its resource is visible in the correct account and region. If a page is empty, explain the design using `docs/architecture.md` and mark that service as pending in the evidence sheet.

## One live transaction to trace

1. Log in to EventHub and register for **event 2**. The browser shows that the request was received.
2. In **SQS**, the main queue's sent/deleted metrics change. A fast worker may consume the message before it is visible in the queue page.
3. In **Step Functions**, open the newest execution. The green path is `ClaimRegistration → ReserveSeat → WriteConfirmed → NotifyConfirmed`.
4. In **DynamoDB**, event 2's `seatsAvailable` decreases by one and `Registrations` shows `CONFIRMED` for that user. The EventHub **Your tickets** page shows the same status.
5. In **SNS** and the confirmed demo inbox, show the email subject, event title, date, and venue. If email is delayed, use the Step Functions execution history and DynamoDB record as proof.
6. For no overbooking, use **event 1** with 2 seats and submit from **three distinct users**. Show two confirmed records, one waitlisted record, and zero remaining seats. A single rejected conditional update is caught and becomes the waitlist path.
7. For failure handling, send a malformed message to the main queue, wait for three receives, then show it in the DLQ and the CloudWatch DLQ alarm. Do this after the successful transaction so a slow alarm cannot interrupt the main demo.

## Evidence sheet

Save screenshots under `docs/screenshots/console/` using names such as `01-vpc.png`, `02-ec2-role.png`, `06-dynamodb-seats-before.png`, `06-dynamodb-seats-after.png`, `08-step-functions-confirmed.png`, `08-step-functions-waitlisted.png`, `10-dlq-alarm.png`, and `14-budget.png`. Add the capture date, AWS account, region, and actual result to `docs/test-plan.md`. Existing UI screenshots show the app design; they do not prove that AWS resources are deployed.

## Honest limitations to explain

- The lab uses HTTP on a single EC2 instance. Use throwaway credentials and do not present this as a production sign-in system.
- The design uses one RDS instance and one EC2 instance. A stopped or failed instance stops that part of the app.
- The workflow has a duplicate claim and an atomic seat decrement, but the MySQL data and DynamoDB writes are not one cross-service transaction. If a later workflow step fails, inspect the failed execution and reconcile the `PROCESSING` record and seat count before repeating a demo.
- SNS email delivery requires the address owner to confirm the subscription, and a new filter policy can take up to 15 minutes to apply. The My tickets page is the status fallback. Budget notifications are alerts, and charges can occur before an alert arrives.
