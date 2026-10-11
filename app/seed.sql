-- EventHub sample data.
-- IMPORTANT: keep the event IDs below in sync with the DynamoDB EventSeats seed
-- in docs/build-guide.md (Phase 3.5):
--   event 1 -> seatsAvailable 2   (small on purpose: good for the race-condition demo)
--   event 2 -> seatsAvailable 50
--   event 3 -> seatsAvailable 0   (instantly WAITLISTED: good for the waitlist demo)

INSERT INTO clubs (id, name, description) VALUES
  (1, 'Coding Club',  'Competitive programming and hackathons'),
  (2, 'Music Club',   'Concerts, jam sessions and open mics');

