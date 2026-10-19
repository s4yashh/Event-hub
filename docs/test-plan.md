# Test Plan — EventHub (BCSE355L)

Run everything from the EC2 instance or the team laptops with a configured CLI
(`aws configure`, region ap-south-1). Fill the "Actual" column during testing —
it becomes the Results section of the report.

| ID | Test | Steps | Expected result | Actual |
|---|---|---|---|---|
| T01 | Sign up + login | Open `http://<EC2-IP>/signup`, create a demo user, opt into email updates, confirm the AWS email, then log in | Redirect to /events; name shown in nav; row inserted in RDS `users`; SNS ticket subscription is Confirmed and filtered to this email | |
| T02 | Event list reads both stores | Open /events after deploying the expanded catalog | 12 event cards with titles from RDS and seat counts from DynamoDB; events 3 and 12 show Waitlist open | |
| T03 | Normal registration | Confirm the demo user's SNS ticket subscription in advance, then register for event 2 (50 seats) | Request received; SQS message consumed; workflow succeeds; EventSeats 50→49; registration CONFIRMED; email names the event, date, and venue | |
| T04 | My registrations page | Open /my | Row shows event title, status CONFIRMED, timestamp | |
| T05 | **Capacity race (no overbooking)** | Run `bash scripts/demo-reset.sh`, then submit three requests for event 1 from three distinct user accounts before the two available seats are taken. Inspect all three Step Functions executions and the DynamoDB items. | Exactly 2 registrations are CONFIRMED and 1 is WAITLISTED; all three workflows succeed and seatsAvailable ends at 0, never negative. | |
| T06 | Waitlist via web flow | Event 3 is seeded with 0 seats — register through the web UI | Email "WAITLISTED"; /my shows WAITLISTED | |
| T07 | SQS message contract | Check queue metrics after a registration or briefly stop the worker and inspect a test message | JSON body has `eventId`, `userId`, `email`, `eventTitle`, `eventDate`, `eventVenue`; message deleted after StartExecution | |
| T08 | **Poison message → DLQ** | `aws sqs send-message --queue-url <QURL> --message-body 'not json'` | Worker logs "bad message"; message returns ~every visibility timeout; after 3 receives it lands in DLQ; **T10 alarm fires and emails** | |
| T09 | Step Functions failure visibility | In Step Functions console → eventhub-register → filter executions by status Failed | Failed executions are visible with full input/output/cause (e.g. T08 does not appear here, but a deliberately broken ARN test would) | |
| T10 | DLQ alarm | CloudWatch → Alarms → eventhub-dlq-not-empty | State ALARM within ~5 min of T08; email notification received | |
| T11 | CPU alarm (optional) | On EC2: `sudo dnf install -y stress || true; stress --cpu 2 --timeout 600` (or temporarily lower the threshold for the demo) | eventhub-cpu-high goes ALARM; email received | |
| T12 | CloudTrail audit | CloudTrail → Event history → filter `Event name = RunInstances` (or `UpdateFunction`… pick a real one like `CreateDBInstance`) | Event listed with user identity, time, source IP — proof of audit trail | |
| T13 | **Duplicate-click / replay** | Click Register twice quickly, or replay the same input twice | First request: CONFIRMED with one seat consumed. Second request: execution SUCCEEDED with output `{"duplicate": true}`; seat unchanged; no second notification. | |
| T14 | Budget tripwire (dry-run) | Budgets → select `monthly-1usd` → verify alert recipients | Alert thresholds and recipients are visible; check actual charges separately in Billing. | |
| T15 | Booking page stays accurate while asynchronous work finishes | Record event 2's displayed seats, book once, and watch the green processing panel without manually refreshing | The page first says processing; after `CONFIRMED`, it shows one fewer seat and links to My tickets. A fresh `/events` load shows the same count. | |
| T16 | Zero-seat event | Register for event 3 when `seatsAvailable=0` | My tickets and the processing panel show `WAITLISTED`; the count remains 0. | |
| T17 | Slow or unavailable worker | Temporarily stop `worker`, submit a disposable booking, then restart it | The page does not claim a confirmed seat while pending. If it takes over 90 seconds, it points to My tickets; after the worker recovers, refreshing shows the actual result. | |
| T18 | Access control on status check | While signed out, open `/api/events/2/registration-status`; while signed in, compare two users' status checks | Signed-out request redirects to login; each signed-in response reads only that user's registration and a current seat count. | |
| T19 | Single last-seat race | Reset demo data, then use two distinct demo users to book event 10 while it has one seat | Exactly one CONFIRMED and one WAITLISTED; event 10 ends at zero seats. | |
| T20 | Added event catalog | Search for event 11 and book with a new demo user, then search for event 12 and join its waitlist | Event 11's seats decrease from 30 to 29; event 12 remains at zero and returns WAITLISTED. | |

## Failure injection quick reference

```bash
# 1) Poison message straight into the queue
aws sqs send-message --queue-url "$QURL" --message-body 'this is not json'

# 2) Watch the DLQ fill
aws sqs get-queue-attributes --queue-url "$QURL" \
  --attribute-names ApproximateNumberOfMessagesVisible

aws sqs receive-message --queue-url "$DLQURL"
```

## Success criteria (for the report)

- No test produces a seat count below 0 (no overbooking under any race).
- Every successful registration workflow ends in exactly one of CONFIRMED / WAITLISTED; failed workflows need investigation in the Step Functions console.
- A message is deleted from the main queue only after a successful StartExecution.
- Poison messages reach the DLQ within ~3 receive attempts and trip the alarm.
- All billed usage stays within free allowances when the account is a free-tier eligible account (see report cost section).
