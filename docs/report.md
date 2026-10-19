# Project Report — EventHub: Event Registration & Ticketing System for College Clubs
**BCSE355L Cloud Architecture Design · VIT Vellore · Team: A / B / C · Region: ap-south-1 (Mumbai)**

> This is a complete outline with draft text. Replace \[bracketed] placeholders, paste your real
> screenshots/numbers after testing, and adjust wording to your team's voice. Section headings are
> the required report structure.

---

## 1. Abstract

EventHub is a cloud-native event registration and ticketing system for college clubs, built on
AWS in the Mumbai region (ap-south-1). Students browse club events, register, and receive a
confirmation email — or a waitlist email if the event is full — with a hard guarantee that seats
are never oversold. The system deliberately uses a serverless orchestration workflow without AWS
Lambda: registration intents are queued in Amazon SQS, consumed by a worker on EC2, and processed
by an AWS Step Functions state machine that performs an atomic conditional write to DynamoDB.
Relational data (users, clubs, events) lives in Amazon RDS for MySQL in private subnets, while
seats and registrations live in Amazon DynamoDB. Security is enforced with IAM roles (no static
keys), security groups, private subnets and KMS encryption; operations are covered by CloudWatch,
CloudTrail and AWS Budgets. The build aims to keep costs low; actual charges must be
measured in Billing for the selected account. This report also presents a production-scale
architecture (load balancing, auto scaling, Multi-AZ, CDN, WAF) that the same design would grow into.

## 2. Problem Statement

College clubs run events with fixed seating. Manual registration (Google Forms + spreadsheets)
has three failure modes: seats get double-booked when two people respond at the same time,
organizers cannot tell who is confirmed versus waitlisted, and there is no audit trail or
notification pipeline. A simple web app that decrements a counter in a relational database can
still oversell under concurrent requests unless the reservation is atomic, and a synchronous
request path loses registrations whenever the backend is slow or unavailable. The problem is
therefore as much a concurrency-and-reliability problem as a web-development problem.

## 3. Objectives

1. Build a functioning web application where students register and log in, browse events and
   register with one click.
2. Guarantee no overbooking under concurrent registrations, using an atomic conditional write
   (DynamoDB `UpdateItem` + `ConditionExpression`).
3. Decouple intake from processing with a queue (SQS) and a dead-letter queue, so no registration
   is silently lost.
4. Implement the reservation workflow without Lambda, using Step Functions' native DynamoDB and
   SNS integrations, with retries, catches and explicit confirmed/waitlisted branches.
5. Notify users asynchronously via SNS with message attributes that support filtered routing.
6. Apply security best practice: private database subnets, least-privilege IAM roles for services,
   MFA for humans, KMS encryption at rest, no static access keys.
7. Operate the system under observability and cost governance: CloudWatch dashboard and alarms,
   CloudTrail audit, Budgets tripwires.
8. Keep the whole build within AWS free-tier allowances and delete every resource after
   evaluation.

## 4. Architecture

*(paste the diagram from `docs/architecture.md` here — Mermaid render or exported image)*

### 4.1 Request flow

1. The student's browser reaches the EC2-hosted Flask app over HTTP (port 80) through the
   Internet Gateway into the public subnet.
2. The app reads users, clubs and events from RDS MySQL in the private subnets (port 3306 allowed
   only from the web security group), and seat counts from DynamoDB.
3. Clicking **Register** publishes the user and event IDs, recipient email, and the event's
   title, date, and venue to the SQS queue and returns
   immediately.
4. A worker process on the same EC2 instance long-polls the queue, calls
   `StepFunctions.StartExecution`, and deletes the message only after the call succeeds.
5. The state machine executes `ReserveSeat` — a DynamoDB conditional update — then takes one of
   two branches: write `CONFIRMED` + SNS publish, or (on `ConditionalCheckFailedException`) write
   `WAITLISTED` + SNS publish.
6. SNS publishes a readable ticket update only to the matching confirmed student subscription;
   a separate SNS topic carries CloudWatch alarms to the team. The student's **My tickets** page
   reads DynamoDB even if email confirmation is pending.

### 4.2 Data model

| Store | Table/DB | Keys | Purpose |
|---|---|---|---|
| RDS MySQL | `users`, `clubs`, `events` | surrogate ids + FK | relational core with joins/constraints |
| DynamoDB | `EventSeats` | `eventId` | hot seat counter, atomic conditional decrement |
| DynamoDB | `Registrations` | `eventId` + `userId` | final status per student per event |

## 5. Service-by-Service Justification

| Service | Role in EventHub | Why this service (viva-ready) |
|---|---|---|
| IAM | group + 3 users, EC2 role, Step Functions role | role-based, keyless access; least privilege; MFA for people |
| VPC + subnets + route tables + IGW | isolated network, public/private split | control over every path; private DB is unreachable from internet |
| Security groups | `eventhub-web-sg`, `eventhub-db-sg` | stateful firewall; DB rule references the web SG, not a CIDR |
| EC2 (t3.micro) | Flask app + SQS worker on systemd | free-tier compute; one box keeps the demo simple but the tier is swappable |
| EBS (8 GiB gp3, encrypted) | OS + app volume | encrypted at rest with AWS-managed key, no extra cost |
| RDS MySQL (db.t3.micro, single-AZ, 20 GB, encrypted) | users/clubs/events | managed relational store; free-tier class; Multi-AZ deferred to scale section |
| DynamoDB (on-demand) | `EventSeats`, `Registrations` | atomic conditional writes = the no-overbooking guarantee |
| SQS + DLQ | `eventhub-registrations` (+DLQ, maxReceiveCount 3) | decoupling, buffering, retry safety net, poison-message quarantine |
| Step Functions (Standard) | `eventhub-register` | serverless orchestration without Lambda; visual history; retries/catches |
| SNS | `eventhub-notifications` and `eventhub-alerts` | filtered student ticket emails and separate team alarm emails |
| SSM Parameter Store | app and workflow parameters incl. 2 SecureStrings | config + secrets centralized; nothing secret in code |
| KMS | AWS-managed keys (`aws/ebs`, `aws/rds`, `aws/ssm`) | encryption at rest everywhere with $0 key cost (trade-off in §11) |
| CloudWatch | dashboard + 3 alarms | operational visibility: backlog, seats contention, failures, CPU |
| CloudTrail | 1 management-events trail + S3 | audit "who did what when"; free single trail |
| Budgets | `zero-spend` + `monthly-1usd` | cost tripwires with team-wide email alerts |

## 6. Security Design

- **Network:** the database has no route to the internet and its security group accepts 3306 only
  from the web tier's security group. SSH is restricted to the team's IPs.
- **Identity:** no static AWS keys anywhere. The app uses an EC2 instance role; the workflow uses
  its own execution role; both are least-privilege JSON (`aws/iam/*.json`). Humans use IAM users
  with MFA; root is used only for account setup.
- **Data:** KMS encryption at rest for EBS, RDS, and SSM SecureStrings; passwords hashed in the
  database; secrets never in code or git.
- **Least privilege in practice:** the group policy denies out-of-syllabus services, blocks
  identity creation/modification by users, and scopes role and PassRole permissions to
  `CloudProject-*`.
- **Auditability:** CloudTrail records every management API call; Step Functions keeps a complete
  execution history of every registration.

## 7. Cost Analysis

The build uses EC2, EBS, RDS, DynamoDB, SQS, Step Functions, SNS, CloudWatch,
CloudTrail, S3, SSM, and Budgets. Charges and free-tier eligibility depend on the
actual account, region, usage, and current AWS pricing. The selected account's
Phase 0 notes describe a **$1 monthly budget alert**; this is a notification,
not a hard limit. Before submitting the report, capture Billing → Bills and
Cost Explorer for the deployment period and enter the actual amount here.

Cost controls built into the design: one small EC2 instance, one single-AZ RDS
instance, no NAT gateway or load balancer, AWS-managed encryption keys, and
cleanup after the assessment. The CloudTrail S3 bucket and monitoring services
also need to be included in the measured total.

**Actual measured cost:** pending live Billing verification.

## 8. Testing and Results

*(copy your filled-in table from `docs/test-plan.md`; key narrative below)*

- **Normal registration (T03):** message queued → consumed in seconds → CONFIRMED email →
  seat 50→49 → /my shows CONFIRMED.
- **Capacity race (T05):** three requests from distinct users against a 2-seat event → exactly 2 CONFIRMED,
  3rd WAITLISTED, `seatsAvailable` ends at 0 and **never below 0**.
- **Waitlist (T06):** 0-seat event → WAITLISTED email via the Catch branch.
- **DLQ (T08+T10):** a non-JSON message retried 3× → landed in DLQ → alarm ALARM → email received.
- **Audit (T12):** CloudTrail event history shows the management events with actor identity.
- Include screenshots: dashboard voltage, race proof, DLQ alarm, CloudTrail entry, budgets page.

## 9. Architecture at Scale (why each was not built here, and how it would fit)

> Rule applied throughout: built version = free-tier-only; this section = the production story.

- **Elastic Load Balancing (ALB):** distributes HTTP traffic across multiple app instances and
  performs health checks. Not built: an ALB has an hourly charge plus LCU usage. Production: one
  internet-facing ALB across two public subnets, forwarding to the app Auto Scaling group.
- **Auto Scaling (ASG):** keeps N healthy app instances and scales out under load. Not built:
  a single instance is within free tier and enough for a demo. Production: an ASG across two AZs
  (min 1, desired 2, max 4) behind the ALB; scale on CPU or SQS backlog.
- **RDS Multi-AZ:** a synchronous standby in a second AZ with automatic failover. Not built:
  doubles instance cost. Production: enabled for the MySQL tier — the app endpoint stays the same.
- **Read Replicas:** asynchronous read-only copies that offload reporting/read traffic. Not built:
  the demo's read volume is trivial. Production: one replica for analytics / My-registrations-style reads.
- **Aurora:** MySQL-compatible managed engine with faster failover, 15 replicas, storage that
  autoscales. Not built: disproportional cost for a student project. Production: natural upgrade
  path from RDS MySQL with minimal code change.
- **CloudFront:** CDN caching static assets and TLS termination at edge locations. Not built:
  charges by data transfer/requests; our static payload is tiny. Production: distribution in
  front of the ALB (static files to S3 origin, dynamic to ALB) with TLS certificates.
- **AWS WAF:** layer-7 request filtering (rate limits, SQL-injection/XSS rules). Not built: an
  attached web ACL has a monthly cost. Production: WAF rules on the CloudFront/ALB, e.g.
  rate-limit Register to blunt seat-race abuse.
- **AWS Shield:** DDoS protection. Shield Standard is always-on and free; Shield Advanced is a
  paid subscription with the DRP team. Not built: Standard is already in effect; Advanced is
  unnecessary for a college event.
- **EFS:** managed elastic NFS shared by many instances. Not built: no shared filesystem need in
  a stateless app design. Production: shared uploads (event posters) across ASG instances.
- **Glacier / S3 lifecycle:** cheap archival storage classes. Not built: no large archives yet.
  Production: CloudTrail logs and past-season event photos archived to Glacier after 90 days.
- **AWS Config:** continuous configuration recording and rules ("is this bucket public?"). Not
  built: per-item recording charges; CloudTrail covers the audit requirement here. Production:
  Config rules on every account, e.g., "EBS must be encrypted", "no security group open 0.0.0.0/0 on 3306".
- **Trusted Advisor:** posture checks (cost, security, limits). Not built into the app: available
  in the console; the full checks set needs a paid support plan. Production/institution-level
  tool, reviewed monthly.
- **Direct Connect:** dedicated private network link from campus to AWS. Not built: physical
  circuit, procurement and monthly port fees. Production: campus datacenter → DX → VPC for
  predictable latency and reduced egress cost.
- **DMS (Database Migration Service):** managed migration/replication between databases. Not
  built: no legacy database to migrate for a greenfield project. Production: used once to move
  from the legacy spreadsheet/MySQL system into RDS with minimal downtime.
- **SMS (Server Migration Service):** migrates on-prem VMs to EC2. Not built: there is no
  on-prem server — this is a new cloud build. Production: relevant if the college's existing
  event portal VM were being lifted and shifted.
- **Snowball / Snowball Edge / Snowmobile:** physical data-transfer appliances for very large or
  offline datasets. Not built: our data is kilobytes; the internet is faster than shipping disks.
  Production (Snowball): annual multi-TB media archives from campus to S3 Glacier; Snowmobile is
  for exabyte-scale moves and would never apply to this system.
- **SWF (Simple Workflow):** the predecessor workflow service requiring custom deciders and
  activity workers. Not chosen: Step Functions gives the same orchestration serverlessly, with
  native retries/catches and visual history — we cover SWF for completeness (Module 7) and
  explain the migration rationale.

**Production architecture (description for the report):** Users reach a CloudFront distribution
(WAF + Shield in front). Static assets come from S3; dynamic API/web traffic is forwarded to an
internet-facing ALB spanning two public subnets. Behind it, an Auto Scaling group of EC2 instances
across two AZs runs the Flask app and stateless workers (AMI + user data, or containers if the
course allowed). The workers consume SQS (DLQ attached) and start the same Step Functions
workflow. RDS MySQL runs Multi-AZ with one read replica; secrets in Parameter Store; encryption
with customer-managed KMS keys; CloudWatch dashboards/alarms, Config rules and CloudTrail
organization trail provide governance; the campus link is Direct Connect. Data archives go to
Glacier; migration tools (DMS/SMS/Snowball) apply only if an on-prem system is being retired.

## 10. Well-Architected Framework Review

- **Operational Excellence:** infrastructure and workflow are declarative (console/CLI steps
  documented, ASL versioned in git, systemd services self-restarting); CloudWatch drives daily
  operations and Step Functions history gives per-registration traceability. Small, reversible
  changes; everything scripted in this repo.
- **Security:** defense in depth — private DB subnets, SG-to-SG rule, MFA on humans, keyless
  service roles, least-privilege JSON, KMS at rest, SecureString secrets, CloudTrail everywhere.
- **Reliability:** the queue + DLQ + retries convert partial failures into recoverable states;
  DynamoDB conditional writes make the critical operation atomic; single-instance compute is the
  known weakness, addressed by ASG/Multi-AZ in the scale design.
- **Performance Efficiency:** async decoupling removes the slow path from the user request;
  on-demand DynamoDB scales with load; RDS is right-sized and would gain a read replica at scale.
- **Cost Optimization:** free-tier sizing, no NAT, no ALB/CDN/WAF in the build, AWS-managed KMS
  keys, budgets with email alerts, and full teardown after evaluation.
- **Sustainability:** right-sizing and managed services minimize idle capacity; asynchronous
  processing avoids over-provisioned servers; S3 lifecycle rules expire logs.

## 11. Limitations

1. Single EC2 instance (no HA); if it fails, registration stops until restart.
2. ~~No idempotency token~~ **Fixed**: the workflow now opens with `ClaimRegistration`, a
   conditional `PutItem` that creates the `(eventId, userId)` record before any seat is reserved.
   A double-click or re-delivered message fails the claim and ends as `{"duplicate": true}` —
   no extra seat is consumed and no second notification is sent.
3. `My registrations` uses a Scan+Filter (Registrations key is eventId+userId); fine at demo
   scale, inefficient at scale.
4. SNS fans out to every subscriber — per-student email needs SES/filtered design.
5. Failure between `ReserveSeat` success and `WriteConfirmed` (e.g., workflow timeout) would
   leak a seat; no compensating transaction is implemented.
6. AWS-managed KMS keys mean no key policies/rotation control (the price of $0).
7. Free-tier dependence: outside free tier the build costs roughly $25–30/month.

## 12. Future Work

- ~~Idempotency~~ **Done (11 Oct 2026):** the workflow opens with a conditional `ClaimRegistration`
  on `(eventId, userId)`; duplicates end as `{"duplicate": true}` without reserving a seat.
  Remaining refinement: surface "already registered" directly in the web UI.
- Compensating transaction (saga pattern) to release a seat if `WriteConfirmed` fails.
- GSI on `Registrations.userId` to replace the Scan with a Query.
- SES integration (out of syllabus) or per-user SNS filter policies for true per-student email.
- Production hardening per §9: ALB + ASG, Multi-AZ RDS, WAF rules, Config rules.
- Seed/reset automation for demo day (a small script; already sketched in the build guide).

## 13. Conclusion

EventHub demonstrates that a small team can design a correct, secure, observable and cost-conscious
cloud system by choosing the right primitive for each job: a queue for decoupling, a conditional
write for concurrency safety, a state machine for orchestration, and a relational store for the
data that needs relationships. The no-overbooking guarantee under a live race, the DLQ failure
path, and the zero-dollar bill are the three results we set out to prove — and the
Architecture-at-Scale section shows how the identical design grows into a production system
without changing its fundamental shape.

## 14. References

- AWS Well-Architected Framework (whitepaper)
- AWS documentation: SQS DLQ/redrive, DynamoDB conditional writes, Step Functions intrinsic
  functions and optimized integrations, SSM Parameter Store, CloudTrail pricing/free tier,
  AWS Budgets
- Course slides: BCSE355L modules 1–8
