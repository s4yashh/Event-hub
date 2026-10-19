# Demo Script — 8 minutes (who says what)

**Pre-demo checklist (run 10 min before):**
- Seed reset: `bash scripts/demo-reset.sh` after the main queue and workflows drain.
  It deletes old demo registrations and restores all twelve starting seat counts;
  the core demo events return to 2/50/0.
  If it purges the DLQ, allow 60 seconds before injecting the failure example.
- Three browser sessions ready, logged in as three different demo users for the race.
- Tabs pre-opened: EC2 console (instance), SQS (both queues), Step Functions console (state
  machine), DynamoDB tables, CloudWatch dashboard, Budgets, CloudTrail Event history, email inbox.
- Worker running: `sudo systemctl status worker`. Prepare three student subscriptions in advance, confirm them, and allow 15 minutes for filters to propagate. Operator inboxes are subscribed to `eventhub-alerts`.

| Time | Speaker | Says / does |
|---|---|---|
| 0:00 | **A** | "EventHub registers students for college club events. We aimed for low cost, avoided Lambda, and designed the seat counter so it cannot overbook. Let me show the architecture in one picture." → draws the flow: browser → EC2 Flask app → RDS MySQL; Register → SQS (+DLQ) → Step Functions → DynamoDB conditional write → SNS email. |
| 0:45 | **A** | "Why this shape: the web tier is in a public subnet; the database is in private subnets with a security group that only accepts MySQL from the web tier; we used no NAT gateway because nothing private initiates outbound traffic — that is our biggest cost saver. DynamoDB exists for one reason: the atomic conditional update `seatsAvailable > 0`, which is the no-overbooking guarantee." |
| 1:30 | **B** | Live demo part 1: sign in as a pre-confirmed demo user → search the twelve-event catalog, then show core demo seats 2/50/0. Register for **event 2**. "The page queues a message — watch." → SQS metrics change; Step Functions execution runs green; inbox shows the event name and **confirmed** subject; My tickets shows CONFIRMED; seats 50 → 49. Show the sign-up page separately if asked. |
| 3:00 | **B+C** | Live demo part 2 — **capacity race**: event 1 has 2 seats. Three distinct users submit registrations together. Exactly two become CONFIRMED and one becomes WAITLISTED. Open DynamoDB → EventSeats: `seatsAvailable = 0`, never negative. Open each Step Functions execution to show the success and caught conditional failure paths. |
| 4:15 | **C** | Waitlist + SNS: register for event 3 (0 seats) → email subject says the student is on the waitlist. Show the student subscription's email filter. "The ticket topic delivers only to the matching confirmed student; a separate topic sends alarms to our team. SNS requires the one-time AWS confirmation, so SES would be our production email choice." |
| 5:00 | **C** | Failure path: inject a poison message: `aws sqs send-message --message-body 'not json'` → worker logs the error and re-tries; after 3 receives the message lands in the **DLQ**; show CloudWatch alarm `eventhub-dlq-not-empty` turning **ALARM** and the alarm email arriving. "No message is ever silently lost." |
| 6:00 | **C** | Monitoring/cost: CloudWatch dashboard (backlog, workflow success/failure, conditional-check failures, CPU) → Budgets page → CloudTrail Event history filtered by `CreateDBInstance`. Say: "Budgets send alerts; they do not stop spending. We check actual charges and delete resources after assessment." |
| 7:00 | **A** | Close: "Component summary: EC2 for compute, RDS for relational data, DynamoDB for atomic counters, SQS for decoupling, Step Functions for orchestration without Lambda, SNS for notification, IAM/KMS/VPC for security, CloudWatch/CloudTrail/Budgets for operations. In production we would add an ALB + Auto Scaling group, Multi-AZ RDS, and CloudFront — laid out in our Architecture-at-Scale section." |
| 7:40 | all | Invite questions. |

**If something breaks live:**
- No email → check SNS subscription confirmed + spam; fall back to showing the execution input/output in the Step Functions console.
- Seats already 0 because of earlier testing → run the seed reset script (have it ready in a terminal).
- Worker not running → `sudo systemctl restart worker`; check `journalctl -u worker -n 50`.

**Viva-friendly one-liners (memorize):**
- "The browser never touches the database for registration — it only drops a message."
- "One message, one workflow execution, one conditional write; the loser goes to the waitlist."
- "The DLQ is proof that we thought about failure, not just the happy path."
