-- Additional EventHub catalog entries. Safe to run on every deployment.
-- Existing club/event IDs and registrations are left untouched.
-- The matching EventSeats items are created by scripts/04-deploy.sh.

INSERT IGNORE INTO clubs (id, name, description) VALUES
  (3, 'Design Club', 'Product design, research and visual storytelling'),
  (4, 'Astronomy Society', 'Night sky observation and space science'),
  (5, 'Robotics Club', 'Hands-on electronics, automation and robots'),
  (6, 'Entrepreneurship Cell', 'Student startups, pitching and entrepreneurship');

INSERT IGNORE INTO events (id, club_id, title, description, event_date, venue) VALUES
  (4, 3, 'UI/UX Design Sprint', 'Team up to redesign a campus app, then present a clickable prototype.', '2026-11-22 10:00:00', 'SJT Innovation Lab'),
  (5, 4, 'Stargazing Night', 'Explore the night sky with guided telescope sessions and constellation stories.', '2026-12-02 19:00:00', 'Main Campus Ground'),
  (6, 5, 'Robotics Build Lab', 'Build and test a line-following robot in a beginner-friendly workshop.', '2026-12-08 14:00:00', 'TT Robotics Lab'),
  (7, 6, 'Startup Pitch Arena', 'Pitch a student startup idea and get feedback from founders and mentors.', '2026-12-13 16:00:00', 'Anna Auditorium'),
  (8, 1, 'Python for Data Science', 'Turn a real dataset into clear charts and practical insights.', '2026-12-16 11:00:00', 'SJT 308'),
  (9, 2, 'Battle of the Bands', 'Campus bands take the stage for an evening of original music.', '2026-12-20 18:00:00', 'Outdoor Amphitheatre'),
  (10, 1, 'Cybersecurity CTF Finals', 'Solve security puzzles and claim the final demo seat.', '2026-11-25 14:00:00', 'SJT Cyber Lab'),
  (11, 3, 'Campus Photography Walk', 'Practice framing and storytelling on a guided campus photo walk.', '2026-12-04 16:00:00', 'Main Gate'),
  (12, 2, 'Poetry Open Mic', 'Share a poem or listen to student voices; this demo event is already full.', '2026-12-18 18:00:00', 'Student Activity Centre');
