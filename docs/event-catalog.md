# EventHub event catalog

The website reads event details from RDS MySQL and live seats from DynamoDB `EventSeats`. These are the **starting capacities**, not the current available seats after bookings.

| ID | Event | Club | Date and time (IST) | Venue | Starting seats |
|---:|---|---|---|---|---:|
| 1 | Node.js Workshop | Coding Club | 20 Nov 2026, 2:00 PM | SJT 402 | 2 |
| 2 | Acoustic Night | Music Club | 28 Nov 2026, 6:30 PM | Anna Auditorium | 50 |
| 3 | Cloud Study Jam | Coding Club | 5 Dec 2026, 10:00 AM | MB 214 | 0 (waitlist demo) |
| 4 | UI/UX Design Sprint | Design Club | 22 Nov 2026, 10:00 AM | SJT Innovation Lab | 36 |
| 5 | Stargazing Night | Astronomy Society | 2 Dec 2026, 7:00 PM | Main Campus Ground | 60 |
| 6 | Robotics Build Lab | Robotics Club | 8 Dec 2026, 2:00 PM | TT Robotics Lab | 24 |
| 7 | Startup Pitch Arena | Entrepreneurship Cell | 13 Dec 2026, 4:00 PM | Anna Auditorium | 80 |
| 8 | Python for Data Science | Coding Club | 16 Dec 2026, 11:00 AM | SJT 308 | 45 |
| 9 | Battle of the Bands | Music Club | 20 Dec 2026, 6:00 PM | Outdoor Amphitheatre | 150 |
| 10 | Cybersecurity CTF Finals | Coding Club | 25 Nov 2026, 2:00 PM | SJT Cyber Lab | 1 (last-seat demo) |
| 11 | Campus Photography Walk | Design Club | 4 Dec 2026, 4:00 PM | Main Gate | 30 |
| 12 | Poetry Open Mic | Music Club | 18 Dec 2026, 6:00 PM | Student Activity Centre | 0 (waitlist demo) |

For the live demo, use **event 10** to show a single last seat, **event 12** for an immediate waitlist, and **event 11** for an ordinary booking with plenty of seats. The original events 1–3 remain available for the planned capacity-race and email demonstration.

Run `bash scripts/04-deploy.sh` on the configured team Mac to upload the app, add the nine additional RDS events, and initialize DynamoDB seat records for IDs 4–12. Re-running it keeps any existing seat counts and registration history. `scripts/demo-reset.sh` intentionally resets all twelve events and deletes demo registrations; use it only before an agreed demo rehearsal.

To verify the live catalog, sign in at `http://13.235.245.147/` and count twelve event cards. In the AWS Console, show **RDS → Databases → eventhub-mysql** for relational event storage and **DynamoDB → Tables → EventSeats → Explore table items** for the twelve seat counters.
