-- EventHub schema — RDS MySQL 8.x
-- Only users, clubs and events live in MySQL.
-- Seats (EventSeats) and registrations (Registrations) live in DynamoDB.
-- Run inside the "eventhub" database:
--   mysql -h <RDS-endpoint> -u eventhubadmin -p eventhub < schema.sql

CREATE TABLE IF NOT EXISTS users (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  name          VARCHAR(100) NOT NULL,
  email         VARCHAR(190) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;

