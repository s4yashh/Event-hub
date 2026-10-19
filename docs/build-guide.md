# Build Guide — EventHub (BCSE355L) · Phases 1–7

**How to use this guide:** one phase at a time. Do every phase on the same day for all three of
you if possible. After each phase, verify using the "Verify" block before moving on. If a console
label differs from this guide (AWS changes UI often), tell your mentor what you see instead of guessing.

**Alternative — scripted CLI build:** `scripts/README.md` describes one bash script per phase that
builds the same resources with the AWS CLI. Phase 1's script (`00-bootstrap-iam.sh`) runs inside
CloudShell while signed in as root, so no root access keys are ever created. If you prefer that
path, run the scripts in order and keep this guide as the reference/backup. Mixing both is fine,
but tell your mentor so nothing gets created twice.

**Region for everything: Asia Pacific (Mumbai) `ap-south-1`.** Check the top-right region selector
before creating any resource.

**Placeholders:** `<ACCOUNT_ID>` = your 12-digit account ID. Team emails = the three students' emails.
Everything is prefixed `eventhub-` (our resources) or `CloudProject-` (IAM) so cleanup is mechanical.

---

## Phase 1 — IAM (who can do what) · Owner: A

**Cost check:** IAM users, groups, roles and policies are **free**. Nothing here can bill you.

### 1.1 Create the team group (sign in as ROOT for Phase 1 only)

Console → search `IAM` → left nav **User groups** → **Create group**.

- Group name: `CloudProject-Admins`
- Don't attach any AWS managed policy yet → **Create group**

Now attach our custom policy:

1. Open `aws/iam/team-group-policy.json` in a text editor and replace every `<ACCOUNT_ID>` with
   your account ID → save.
2. IAM → **Policies** → **Create policy** → **JSON** tab → paste the whole edited file →
   **Next** → Policy name: `CloudProject-Team-Policy` → **Create policy**.
3. Back to **User groups** → `CloudProject-Admins` → **Permissions** tab → **Add permissions** →
   **Attach policies** → search `CloudProject-Team-Policy` → attach.

CLI equivalent:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws iam create-group --group-name CloudProject-Admins
# after editing the file:
aws iam create-policy --policy-name CloudProject-Team-Policy \
  --policy-document file://aws/iam/team-group-policy.json
aws iam attach-group-policy --group-name CloudProject-Admins \
  --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/CloudProject-Team-Policy
```

### 1.2 Create the three users (one per team member)

IAM → **Users** → **Create user** (repeat 3×):

- User name: the person's name (e.g. `arjun`, `bhavya`, `chitra`)
- **Provide user access to the AWS Management Console** ✔
- **I want to create an IAM user** → Custom password (set one, share via password manager)
- Untick "Users must create a new password at next sign-in" (optional, simpler)
- **Next** → add to group `CloudProject-Admins` → **Next** → **Create user**

Then, **each person logs in with their own user** (console URL: `https://<ACCOUNT_ID>.signin.aws.amazon.com/console`)
and immediately:

1. **Sets up MFA**: IAM → Users → (their name) → Security credentials → Assign MFA device →
   authenticator app → name it `mfa` → scan → 2 codes → done.
2. **Creates their own CLI access key**: Security credentials → **Create access key** →
   "Command Line Interface (CLI)" → download/save it once. Then on their laptop:
   ```bash
   aws configure
   # Access key / secret: (theirs — never root's, never committed to git)
   # region: ap-south-1   output: json
   aws sts get-caller-identity   # should show their own user ARN
   ```

> Hard rule: no access keys in code, no root keys ever. Each person keeps their own key in
> `~/.aws/credentials` only. Delete the key at project end (cleanup checklist).

### 1.3 EC2 instance role (the web app's identity)

IAM → **Roles** → **Create role**:

- Trusted entity: **AWS service** → Use case: **EC2** → Next
- **Create policy** (new tab) → JSON → paste `aws/iam/ec2-role-policy.json` with
  `<ACCOUNT_ID>` replaced → name `CloudProject-EC2-Policy` → Create.
- Back in the role wizard: search/select `CloudProject-EC2-Policy` → Next
- Role name: `CloudProject-EC2-Role` → **Create role**

Then create the instance profile (console does it automatically when creating a role for EC2;
via CLI you must do it):

```bash
aws iam create-instance-profile --instance-profile-name CloudProject-EC2-Profile
aws iam add-role-to-instance-profile \
  --instance-profile-name CloudProject-EC2-Profile --role-name CloudProject-EC2-Role
```

### 1.4 Step Functions execution role

IAM → **Roles** → **Create role**:

- Trusted entity: **AWS service** → Use case: it may not list "Step Functions" — under
  "Other AWS services" pick **Step Functions** (trust service `states.amazonaws.com`).
- Attach `aws/iam/stepfunctions-role-policy.json` (paste, `<ACCOUNT_ID>` replaced,
  name it `CloudProject-StepFunctions-Policy`).
- Role name: `CloudProject-StepFunctions-Role` → Create.

**Verify:** IAM → Users shows 3 users; each user's own console shows MFA active;
`aws sts get-caller-identity` works for each person; 2 custom policies + 2 roles exist.

**Viva note:** Why three layers of identity? (1) People log in as IAM users in a group with
least privilege; (2) the EC2 role gives the server its permissions without any key on disk;
(3) the Step Functions role lets the workflow touch only the one DynamoDB table pair and one SNS
topic. If you see `AccessDenied` later, it is almost always one of these two role policies.

---

## Phase 2 — VPC and network · Owner: A

**Cost check:** VPC, subnets, route tables, internet gateway, security groups are **free**.
We deliberately do **not** create a NAT Gateway (≈ $1/day) — that is why private subnets have no
outbound internet route.

### 2.1 VPC

VPC console → **Create VPC** → **VPC only**:

- Name tag: `eventhub-vpc`, IPv4 CIDR: `10.0.0.0/16`
- **Create VPC** → then select it → **Actions → Edit VPC settings** → tick
  **Enable DNS hostnames** → Save.

### 2.2 Subnets (1 public + 2 private in two AZs)

| Name | CIDR | AZ | Extra |
|---|---|---|---|
| `eventhub-public-1a` | 10.0.1.0/24 | ap-south-1a | Actions → **Edit subnet settings → Enable auto-assign public IPv4** ✔ |
| `eventhub-private-1a` | 10.0.2.0/24 | ap-south-1a | — |
| `eventhub-private-1b` | 10.0.3.0/24 | ap-south-1b | — |

(If your account doesn't offer ap-south-1a/1b in the dropdown, pick any two AZs —
for example 1a + 1b is just convention. What matters: public + private share one AZ,
and the two private subnets are in **different** AZs.)

CLI:

```bash
aws ec2 create-subnet --vpc-id <VPC_ID> --cidr-block 10.0.1.0/24 \
  --availability-zone ap-south-1a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=eventhub-public-1a}]'
# ...same pattern for the two private subnets (10.0.2.0/24 in 1a, 10.0.3.0/24 in 1b)
aws ec2 modify-subnet-attribute --subnet-id <PUBLIC_SUBNET_ID> --map-public-ip-on-launch
```

### 2.3 Internet Gateway

VPC → **Internet gateways** → **Create internet gateway** → name `eventhub-igw` → Create →
select it → **Actions → Attach to VPC** → `eventhub-vpc`.

### 2.4 Route tables

1. VPC → **Route tables** → **Create route table** → name `eventhub-rt-public`,
   VPC `eventhub-vpc` → Create → open it → **Routes → Edit routes → Add route**:
   Destination `0.0.0.0/0`, Target: **Internet Gateway → eventhub-igw** → Save.
   → **Subnet associations → Edit** → tick `eventhub-public-1a` → Save.
2. Create `eventhub-rt-private` (same VPC, no extra routes — only the automatic local route) →
   associate **both** private subnets.

Leave the "main" route table untouched; explicit route tables make the design readable in the report.

### 2.5 Security groups

EC2 console → **Security groups** → **Create security group**:

1. `eventhub-web-sg` (VPC `eventhub-vpc`):
   - Inbound: **HTTP 80** from `0.0.0.0/0`; **SSH 22** from **My IP** (dropdown chooses your IP/32).
   - Outbound: leave default (all traffic) — the instance needs outbound (repos, AWS APIs).
2. `eventhub-db-sg` (same VPC):
   - Inbound: **MySQL/Aurora 3306**, Source: **Custom → `eventhub-web-sg`** (type "sg-" and pick it).
   - Outbound: default.

### 2.6 DB subnet group

RDS console → **Subnet groups** → **Create DB subnet group** → name `eventhub-db-subnet-group`,
VPC `eventhub-vpc`, Availability Zones: ap-south-1a + ap-south-1b, Subnets: `eventhub-private-1a`
and `eventhub-private-1b` → Create.

**Verify:** VPC has 3 subnets; public route table route `0.0.0.0/0 → igw`; public subnet shows
auto-assign public IPv4 = Yes; db-sg's 3306 rule shows **sg-(eventhub-web-sg)** as source, not an IP.

**Viva note:** Why two private AZs if RDS is single-AZ? Because an RDS DB subnet group requires
subnets in at least two AZs; the instance still runs in one. Why no NAT? Cost; the only private
resource is RDS, which never initiates outbound traffic.

---

## Phase 3 — Data stores · Owner: B (A helps with console)

**Cost check:** On a free-tier-eligible account: RDS db.t3.micro (or db.t2.micro) = 750 h/month,
20 GB storage + backups included; DynamoDB on-demand at demo volume ≈ $0. **Verify your account's
free tier first (Phase 0)!** Notes: RDS **auto-restarts a stopped instance after 7 days** — plan
for it; a stopped RDS still bills storage; delete it at project end (cleanup checklist).

### 3.1 SSM parameters (do this before RDS so the password never floats around)

Systems Manager console → **Parameter Store** → **Create parameter** (repeat):

| Name | Type | Value |
|---|---|---|
| `/eventhub/db-user` | String | `eventhubadmin` |
| `/eventhub/db-name` | String | `eventhub` |
| `/eventhub/db-password` | **SecureString** | a freshly generated strong password |

Generate a password first: `openssl rand -base64 18` (store it ONLY in SSM + your password manager).

CLI:

```bash
aws ssm put-parameter --name /eventhub/db-user --type String --value eventhubadmin
aws ssm put-parameter --name /eventhub/db-name --type String --value eventhub
aws ssm put-parameter --name /eventhub/db-password --type SecureString --value "$(openssl rand -base64 18)"
```

### 3.2 Create RDS MySQL

RDS → **Create database** → **Standard create** → Engine: **MySQL** (keep the version the console
recommends; 8.x) → Template: **Free tier** if offered, else Dev/Test.

- DB instance identifier: `eventhub-mysql`
- Master username: `eventhubadmin`; Credentials management: **Self managed** → password =
  paste the same value you just stored in SSM (**careful: spaces/symbols are fine, but copy exactly**).
- DB instance class: whichever shows **"Free tier eligible"** — `db.t3.micro` (or `db.t2.micro`)
- Storage: **20 GiB**, **gp2** (switch off autoscaling), **Enable storage encryption: Yes**
  (choose the default `aws/rds` key — no extra cost)
- Availability: **Single-AZ** (`ap-south-1a`), **Do not** create a standby
- Connectivity: VPC `eventhub-vpc`; **Public access: No**; subnet group `eventhub-db-subnet-group`;
  security group `eventhub-db-sg` (deselect `default`)
- Database authentication: **Password authentication**
- Additional: **Initial database name: `eventhub`**; **Automated backups: uncheck** (retention 0 —
  keeps storage cost at zero; trade-off noted in the report); **Deletion protection: off** (easy
  cleanup); auto minor version upgrade: on.
- **Create database** (~5–10 min).

CLI (long but copy-paste-able):

```bash
aws rds create-db-instance \
  --db-instance-identifier eventhub-mysql \
  --db-instance-class db.t3.micro \
  --engine mysql \
  --master-username eventhubadmin \
  --master-user-password "$(aws ssm get-parameter --name /eventhub/db-password --with-decryption --query Parameter.Value --output text)" \
  --allocated-storage 20 --storage-type gp2 --storage-encrypted \
  --db-subnet-group-name eventhub-db-subnet-group \
  --vpc-security-group-ids <db-sg-id> \
  --no-publicly-accessible --no-multi-az \
  --backup-retention-period 0 --no-deletion-protection \
  --db-name eventhub
```

### 3.3 After RDS is available: store the endpoint

RDS → Databases → `eventhub-mysql` → copy **Endpoint** (looks like
`eventhub-mysql.abc123.ap-south-1.rds.amazonaws.com`) → Parameter Store →
`/eventhub/db-host` (String).

### 3.4 Create DynamoDB tables

DynamoDB console → **Create table** (repeat 2×):

1. Name `EventSeats`; Partition key `eventId` (String); Table settings: **On-demand** → Create.
2. Name `Registrations`; Partition key `eventId` (String) + Sort key `userId` (String);
   **On-demand** → Create.

### 3.5 Seed EventSeats (amounts match `app/seed.sql`)

DynamoDB → `EventSeats` → **Explore table items → Create item** → switch to **JSON view**):

```json
{"eventId": "1", "seatsAvailable": 2}
{"eventId": "2", "seatsAvailable": 50}
{"eventId": "3", "seatsAvailable": 0}
```

CLI:

```bash
aws dynamodb put-item --table-name EventSeats --item '{"eventId":{"S":"1"},"seatsAvailable":{"N":"2"}}'
aws dynamodb put-item --table-name EventSeats --item '{"eventId":{"S":"2"},"seatsAvailable":{"N":"50"}}'
aws dynamodb put-item --table-name EventSeats --item '{"eventId":{"S":"3"},"seatsAvailable":{"N":"0"}}'
```

**Verify:** both tables Active; 3 items in EventSeats; `/eventhub/db-host` matches the RDS
endpoint exactly.

The expanded catalog in `docs/event-catalog.md` adds event IDs 4–12 during
`bash scripts/04-deploy.sh`. That command creates only missing seat items, so a
redeploy does not reset bookings.

**Viva note:** Why MySQL *and* DynamoDB? MySQL gives relationships and constraints for
users/clubs/events; DynamoDB gives an atomic conditional counter (`seatsAvailable > :zero`)
that makes overbooking impossible, cheaply, at any concurrency.

---

## Phase 4 — EC2 + application deployment · Owner: A+B (A launches, B deploys)

**Cost check:** Free-tier accounts: 750 h/month of t3.micro (or t2.micro). EBS 8 GiB gp3 is inside
the 30 GB allowance. **No Elastic IP** — we use the auto-assigned public IPv4 (free while the
instance runs; the IP changes if you stop/start, that is fine). Verify free-tier eligibility in the
EC2 launch wizard ("Free tier eligible" label).

### 4.1 Key pair

EC2 → **Key pairs** → **Create key pair** → name `eventhub-key`, type RSA, format `.pem` →
download → `chmod 400 eventhub-key.pem` on your laptop.

### 4.2 Launch the instance

EC2 → **Launch instance**:

- Name: `eventhub-web`; **Amazon Linux 2023** AMI (64-bit x86)
- Instance type: whichever shows **Free tier eligible** (`t3.micro` or `t2.micro`)
- Key pair: `eventhub-key`
- Network settings → Edit: VPC `eventhub-vpc`; subnet `eventhub-public-1a`;
  **Auto-assign public IP: Enable**; firewall: **Select existing security group → eventhub-web-sg**
- Advanced → IAM instance profile: **CloudProject-EC2-Role** (when you create a role for EC2 in the
  console, AWS auto-creates an instance profile with the same name; if you used the CLI steps
  instead, pick `CloudProject-EC2-Profile`)
- Storage: 8 GiB **gp3**, **Encrypted: Yes** (default `aws/ebs` key)
- **Launch instance**

CLI sketch:

```bash
aws ec2 run-instances --image-id <AL2023-AMI-ID> --instance-type t3.micro \
  --key-name eventhub-key --security-group-ids <web-sg-id> --subnet-id <public-subnet-id> \
  --iam-instance-profile Name=CloudProject-EC2-Profile \
  --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=8,VolumeType=gp3,Encrypted=true}' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=eventhub-web}]'
```

### 4.3 First login + mysql client

```bash
ssh -i eventhub-key.pem ec2-user@<EC2-PUBLIC-IP>
sudo dnf install -y mariadb105        # MySQL-compatible client (if `mysql` missing, use `mariadb`)
```

### 4.4 Load schema and sample data (still on EC2)

Copy `app/schema.sql`, `app/seed.sql`, and `app/seed-extra.sql` to the instance (scp from laptop), then:

```bash
mysql -h <RDS-endpoint> -u eventhubadmin -p eventhub < schema.sql
mysql -h <RDS-endpoint> -u eventhubadmin -p eventhub < seed.sql
mysql -h <RDS-endpoint> -u eventhubadmin -p eventhub < seed-extra.sql
mysql -h <RDS-endpoint> -u eventhubadmin -p eventhub -e "SELECT * FROM events;"
```

For the nine additional events, run `bash scripts/04-deploy.sh` from the team Mac to
initialize their DynamoDB seat items as well. SQL rows alone show
"Availability updating" in the website.

### 4.5 Deploy the app

Create the Flask secret parameter (needed at app startup):

```bash
aws ssm put-parameter --name /eventhub/flask-secret --type SecureString --value "$(openssl rand -hex 32)"
```

Copy the app and bootstrap:

```bash
# from your laptop, in the project folder:
scp -i eventhub-key.pem -r app/ ec2-user@<EC2-PUBLIC-IP>:~/eventhub-app
ssh -i eventhub-key.pem ec2-user@<EC2-PUBLIC-IP> 'sudo bash ~/eventhub-app/setup.sh'
```

The script installs Python, builds `/opt/eventhub` + venv, installs both systemd units, and starts
the web app (`eventhub.service`). The worker is intentionally **not** started yet (Phase 5).

### 4.6 Verify

```bash
sudo systemctl status eventhub
curl -s -o /dev/null -w "%{http_code}\n" http://localhost/    # expect 200 (landing page)
```

From your laptop browser: `http://<EC2-PUBLIC-IP>/` → sign up → log in → /events shows 12 events
after `04-deploy.sh`, including the three core demo events with seats 2 / 50 / full.
(Registering now would fail because the queue doesn't exist yet — that's Phase 5.)

**Viva note:** The instance has *no* AWS keys on disk; boto3 fetched temporary credentials from the
instance metadata service (IMDS) via the role. EBS root volume is encrypted with KMS at rest.

---

## Phase 5 — Queue, notifications, workflow · Owner: C (B verifies)

**Cost check:** SQS/SNS free-tier allowances are large (1M requests/month class); Step Functions
Standard = 4,000 free state transitions/month. **Keep state machine logging OFF** (CloudWatch Logs
ingestion would be billed, and it is not needed for the demo). Everything here ≈ $0.

### 5.1 SQS: DLQ first, then the main queue

SQS console → **Create queue** → type **Standard**:

1. `eventhub-registrations-dlq` → Create. (No special settings.)
2. `eventhub-registrations`:
   - Visibility timeout: **30 seconds**
   - **Dead-letter queue: Enabled** → choose `eventhub-registrations-dlq` → **Maximum receives: 3**

CLI:

```bash
DLQ_ARN=$(aws sqs create-queue --queue-name eventhub-registrations-dlq \
  --query QueueUrl --output text)
aws sqs create-queue --queue-name eventhub-registrations \
  --attributes '{"VisibilityTimeout":"30","RedrivePolicy":"{\"deadLetterTargetArn\":\"arn:aws:sqs:ap-south-1:<ACCOUNT_ID>:eventhub-registrations-dlq\",\"maxReceiveCount\":\"3\"}"}'
```

### 5.2 SNS ticket and alarm topics

SNS console → **Topics** → **Create topic** → Standard → create two topics:

- `eventhub-notifications`: student ticket results only. The app requests a filtered
  subscription when a student opts in during sign-up or uses My tickets → Request email updates.
  Each student must confirm the AWS email.
- `eventhub-alerts`: operator CloudWatch alarms only. Subscribe the team inboxes here,
  and confirm each AWS email.

Do not put an unfiltered team subscription on `eventhub-notifications`: it would receive
every student's ticket message. If one exists from an earlier build, remove it in SNS.
For a live email demo, create and confirm student subscriptions at least 15 minutes
before registering; SNS filter-policy changes can take time to propagate.

Filter-policy demo: open one student's ticket subscription and show that its policy
matches that student's email attribute. `aws/sns/subscription-filter-policy.json`
shows how to narrow that subscription to WAITLISTED messages too; replace the
example email before using it. A status-only filter on the student topic would
expose all waitlisted event updates to that subscriber.

### 5.3 Step Functions state machine

1. Copy `aws/stepfunctions/register-event.asl.json` to a temporary file and replace
   `<ACCOUNT_ID>` with the current account ID in that copy. Keep the tracked template reusable.
2. Step Functions console → **Create state machine** → **Blank** → Name `eventhub-register` →
   Type: **Standard** → paste the edited JSON in the **Code** editor.
3. Execution role: **Choose an existing role → CloudProject-StepFunctions-Role**.
4. **Logging: Off. X-Ray tracing: Off.** → **Create**.

CLI:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
mkdir -p aws/stepfunctions/rendered
sed "s/<ACCOUNT_ID>/${ACCOUNT_ID}/g" aws/stepfunctions/register-event.asl.json \
  > aws/stepfunctions/rendered/register-event.asl.json
aws stepfunctions create-state-machine --name eventhub-register \
  --definition file://aws/stepfunctions/rendered/register-event.asl.json \
  --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/CloudProject-StepFunctions-Role"
```

Test it from the console: **Start execution** with input
`{"eventId":"2","userId":"9000","email":"test@example.com","eventTitle":"Acoustic Night","eventDate":"28 Nov 2026, 06:30 PM","eventVenue":"Anna Auditorium"}` → watch it go
ClaimRegistration → ReserveSeat → WriteConfirmed → NotifyConfirmed (green), and seats 50 → 49.
For event 1, use **three different user IDs** against its two seats. The third follows
WriteWaitlisted. Reusing a user ID demonstrates duplicate protection instead.

### 5.4 Finish config + start the worker

Parameter Store → create:

| Name | Value |
|---|---|
| `/eventhub/queue-url` | the `eventhub-registrations` queue URL |
| `/eventhub/sns-topic-arn` | the `eventhub-notifications` ARN |
| `/eventhub/alerts-topic-arn` | the `eventhub-alerts` ARN |
| `/eventhub/state-machine-arn` | the `eventhub-register` ARN (a full ARN, not a URL) |

Then on EC2:

```bash
sudo systemctl start worker
sudo systemctl status worker
sudo journalctl -u worker -f        # watch it long-poll
```

### 5.5 End-to-end smoke test

In the browser: log in → Register for event 2 → within ~2 s you should see:
SQS message consumed → execution succeeded → email **CONFIRMED** → /my shows CONFIRMED,
seats 49. Then register for event 1 three times (or with 2 accounts) until it goes WAITLISTED.

**Viva note:** Why queue in the middle? The web request must be fast and must not lose
registrations during traffic spikes; SQS absorbs bursts and retries. Why delete only after
StartExecution? Because that is the point where responsibility for the work transfers to the
workflow; failures before that get retried automatically, and a message that keeps failing lands
in the DLQ after 3 receives instead of vanishing.

---

## Phase 6 — Monitoring, audit, cost guardrails · Owner: C (A reviews)

**Cost check:** CloudWatch: 10 custom metrics/10 alarms free tier class — we use 3 alarms.
CloudTrail: **one** management-events trail is free; **do NOT enable data events** (billed).
Its S3 log storage is a few KB — add a lifecycle rule (below) to keep it tidy. Budgets: already
created in Phase 0, free.

### 6.1 CloudWatch dashboard

CloudWatch → **Dashboards** → **Create dashboard** → name `eventhub-dashboard` →
**Add widget** for each (Line/Number as you prefer, region ap-south-1):

| Widget | Namespace | Metric | Dimension |
|---|---|---|---|
| Queue backlog | AWS/SQS | ApproximateNumberOfMessagesVisible | QueueName = eventhub-registrations |
| DLQ depth | AWS/SQS | ApproximateNumberOfMessagesVisible | QueueName = eventhub-registrations-dlq |
| Workflow successes | AWS/States | ExecutionsSucceeded | StateMachineArn = eventhub-register |
| Workflow failures | AWS/States | ExecutionsFailed | StateMachineArn = eventhub-register |
| Conditional seat failures (waitlists) | AWS/DynamoDB | ConditionalCheckFailedRequests | TableName = EventSeats |
| EC2 CPU | AWS/EC2 | CPUUtilization | InstanceId = eventhub-web |

### 6.2 Three alarms

CloudWatch → **Alarms → All alarms → Create alarm → Select metric**:

1. `eventhub-cpu-high`: AWS/EC2 → Per-Instance Metrics → CPUUtilization(eventhub-web) →
   Statistic Average, Period 5 min, Threshold: **Greater than 70** → notification:
   use `eventhub-alerts` and confirm the operator inbox subscription → name it, Create.
2. `eventhub-dlq-not-empty`: AWS/SQS → Queue Metrics → ApproximateNumberOfMessagesVisible
   (eventhub-registrations-dlq) → Statistic Maximum, Period 5 min, Threshold **Greater than 0** →
   **Treat missing data as notBreaching** → same SNS action.
3. `eventhub-sfn-failed`: AWS/States → ExecutionsFailed(eventhub-register) → Statistic Sum,
   Period 5 min, Threshold **Greater than or equal to 1** → same SNS action.

CLI example (DLQ alarm):

```bash
aws cloudwatch put-metric-alarm --alarm-name eventhub-dlq-not-empty \
  --namespace AWS/SQS --metric-name ApproximateNumberOfMessagesVisible \
  --dimensions Name=QueueName,Value=eventhub-registrations-dlq \
  --statistic Maximum --period 300 --evaluation-periods 1 \
  --threshold 0 --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching \
  --alarm-actions <SNS-topic-arn>
```

### 6.3 CloudTrail

CloudTrail → **Trails → Create trail**:

- Name `eventhub-trail`; **Create new S3 bucket**: `eventhub-cloudtrail-<ACCOUNT_ID>`
- **Management events** only; **do not** tick S3 data events
- CloudWatch Logs: off → Create trail (logging auto-starts)

Then S3 → the trail bucket → **Management → Create lifecycle rule** → name `expire-30d` →
Apply to all objects → **Expire current versions after 30 days** → Create.

Lookup proof (for the report): CloudTrail → **Event history** → filter Event name `CreateDBInstance`
or `RunInstances` → expand → user identity, time, source IP.

**Viva note:** CloudTrail answers *"who did what, when"* (governance); CloudWatch answers
*"is the system healthy right now"* (operations). Budgets answer *"are we about to pay money"*.

---

## Phase 7 — End-to-end testing, report evidence, cleanup

1. Run `docs/test-plan.md` T01–T14. **T05 (race)** and **T08 (poison → DLQ → alarm)** are the
   showpieces — screenshot everything.
2. After queues and workflows drain, run `bash scripts/demo-reset.sh` before the demo.
   This clears old demo tickets and restores seat counts to 2/50/0.
3. When the project is evaluated and the demo is over: run `docs/cleanup-checklist.md`
   **top to bottom on the same day**. Check the actual charges in Billing → Bills
   and Cost Explorer, and confirm no volumes/snapshots/Elastic IPs remain.

**Final viva note:** the whole point of this architecture is every Well-Architected trade-off:
reliability (queue + retries + DLQ), performance (async decoupling), cost (free tiers, no NAT),
security (private DB + roles + encryption + least privilege) and operational excellence
(CloudWatch + CloudTrail + Step Functions history).
