-- EventHub sample data.
-- IMPORTANT: keep the event IDs below in sync with the DynamoDB EventSeats seed
-- in docs/build-guide.md (Phase 3.5):
--   event 1 -> seatsAvailable 2   (small on purpose: good for the race-condition demo)
--   event 2 -> seatsAvailable 50
--   event 3 -> seatsAvailable 0   (instantly WAITLISTED: good for the waitlist demo)

INSERT INTO clubs (id, name, description) VALUES
  (1, 'Coding Club',  'Competitive programming and hackathons'),
  (2, 'Music Club',   'Concerts, jam sessions and open mics');

INSERT INTO events (id, club_id, title, description, event_date, venue) VALUES
  (1, 1, 'Node.js Workshop',        'Hands-on REST API workshop. Bring a laptop.', '2026-11-20 14:00:00', 'SJT 402'),
  (2, 2, 'Acoustic Night',          'Open mic evening with the Music Club.',       '2026-11-28 18:30:00', 'Anna Auditorium'),
  (3, 1, 'Cloud Study Jam',         'AWS fundamentals study jam (already full).',  '2026-12-05 10:00:00', 'MB 214');

-- Demo users: create them through the web /signup page so the app stores a
-- proper password hash. Any personal email address works.
-- The app stores a password hash, so insert demo users through /signup.
