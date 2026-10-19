# Viva Questions & Model Answers — EventHub (BCSE355L)

**Q1. Why SQS between the web app and the processing?**
To decouple. The student's HTTP request returns immediately after the message is safely durably
stored; bursts of registrations are absorbed by the queue; and if the workflow is momentarily
failing, messages are retried (then parked in the DLQ) instead of being lost with a crashed
request. It also lets the same queue feed more workers later without changing the web app.

**Q2. Why DynamoDB conditional writes instead of a MySQL transaction for seats?**
Both can prevent overbooking; we chose DynamoDB because `UpdateItem` with
`ConditionExpression "seatsAvailable > :zero"` is a single atomic, server-side operation that
scales horizontally under high contention, and it demonstrates a second data service from the
syllabus. MySQL stores the relational data (users, clubs, events) where joins and foreign keys
matter. Each store does what it is best at.

**Q3. Why private subnets for RDS? Why no NAT Gateway?**
Private subnets have no route to the Internet Gateway, so the database has no inbound path from
the internet at all; only the web security group can reach port 3306. A NAT Gateway (~$1/day +
data processing) would only be needed if private resources initiated outbound traffic — ours
never do, so we skip it. That is a deliberate cost/security choice, and in production (where
private app servers exist) we would add NAT or VPC endpoints.

**Q4. Why no Lambda?**
Outside the allowed syllabus for this project. And it is not needed: Step Functions' optimized
integrations call DynamoDB and SNS directly, so the entire workflow is declarative, versioned and
visible in the execution history — arguably easier to explain and audit than hidden Lambda code.

**Q5. Why Step Functions instead of SWF?**
SWF is the older service; it requires your own deciders/workers and is effectively legacy.
Step Functions is serverless, has native error handling (Retry/Catch), visual history, and
optimized integrations with the services we already use. We cover SWF in the Architecture-at-Scale
section and explain why we chose Step Functions.

**Q6. How exactly does "no overbooking" work?**
`ReserveSeat` performs `SET seatsAvailable = seatsAvailable - :one` with
`ConditionExpression "seatsAvailable > :zero"`. DynamoDB evaluates the condition and applies the
update atomically per item, so two simultaneous executions serialize: one succeeds, the other
receives `ConditionalCheckFailedException`, which we Catch into the waitlist branch. The counter
can never go below zero even under a race.

**Q7. What happens if the worker crashes after StartExecution but before DeleteMessage?**
The message becomes visible again after the 30 s visibility timeout and is processed again.
Step Functions starts a second execution, but the workflow is duplicate-safe: the first state,
`ClaimRegistration`, conditionally creates the `(eventId, userId)` record before touching the
seat counter. The second execution fails that condition and ends as `{"duplicate": true}` without
reserving another seat or sending another notification. This was verified with a sequential
replay and with two identical executions running at the same instant.

**Q8. Why does the DLQ exist and how is it wired?**
The main queue has a RedrivePolicy: after `maxReceiveCount = 3` failed receives, the message is
moved to `eventhub-registrations-dlq`. That preserves poison messages for inspection instead of
losing or looping them forever, and a CloudWatch alarm on DLQ depth alerts us by email.
In the demo, a non-JSON message shows the full path.

**Q9. How do you keep student ticket emails private?**
We use two SNS topics: `eventhub-notifications` for student tickets and `eventhub-alerts`
for team alarms. Every student subscription on the ticket topic has an email-attribute
filter, so a publish is delivered only to the matching confirmed subscriber. An
unfiltered subscription would receive every ticket and must not be used on that topic.
SNS still requires a one-time AWS confirmation and has limited email styling. For a
production customer-email system we would use SES, which is outside our syllabus.

**Q10. Why is the EC2 role safer than access keys?**
The instance gets short-lived rotated credentials from IMDS; nothing is stored in code or on
disk, so a leaked repository or snapshot exposes no keys. Each service role is least privilege:
the EC2 role can only read the two tables, use the one queue, start the one state machine, read
`/eventhub/*` parameters and decrypt via SSM. The Step Functions role can only update EventSeats,
put Registrations and publish to one topic.

**Q11. Why VPC endpoints? (we did not build one)**
A DynamoDB gateway endpoint is free and would keep DynamoDB/SQS traffic on the AWS network
(instead of via the internet gateway) — a security and cost nicety. Optional in the report.

**Q12. How does this scale?**
The queue absorbs bursts; the worker is stateless, so more workers can consume in parallel;
DynamoDB and Step Functions scale managed-side; the EC2+RDS single-instance tier is the
bottleneck. Production: ALB + Auto Scaling group across AZs, Multi-AZ RDS with read replicas,
CloudFront for static content — the Architecture-at-Scale section.

**Q13. What about cost — how do you keep this at zero?**
Free-tier sizing everywhere (db.t3.micro RDS, t3.micro EC2, 8 GiB gp3), no NAT/ALB/CloudFront/
Multi-AZ, on-demand DynamoDB at demo volume, one free CloudTrail management trail, no data events,
email-only SNS, state machine logging off, two free budgets as tripwires, and full deletion after
evaluation per the cleanup checklist.

**Q14. Where are passwords stored, and how are they protected?**
The RDS master password and the Flask session secret are SecureString parameters in SSM
Parameter Store, encrypted with KMS (AWS-managed `aws/ssm` key) and read at runtime by the
instance role. Users' web passwords are stored as salted hashes (Werkzeug) in MySQL — never
plaintext.

**Q15. Explain the data split once more.**
MySQL: users, clubs, events (relational, joined, constrained, low write rate). DynamoDB:
EventSeats (hot counter, atomic decrement) and Registrations (per event+user status record,
written exactly once per registration by the workflow). The web app reads both to render pages.

**Q16. Which Well-Architected pillars did you address?**
All six, each with a concrete artifact: Operational Excellence (CloudWatch dashboard, CloudTrail,
runbooks), Security (private DB, least-privilege roles, KMS encryption, MFA), Reliability
(queue, retries, DLQ, conditional writes), Performance Efficiency (async decoupling, on-demand
DynamoDB), Cost Optimization (free tiers, no NAT, budgets), Sustainability (right-sizing,
managed services).
