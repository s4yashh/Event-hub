#!/usr/bin/env bash
# EventHub — reset demo state before each practice run / demo.
# Seats: event 1 -> 2, event 2 -> 50, event 3 -> 0. Queues purged.
# Run: bash scripts/demo-reset.sh
set -euo pipefail

REGION="${REGION:-ap-south-1}"
export AWS_DEFAULT_REGION="$REGION"

seat() { # eventId seats
  aws dynamodb update-item --table-name EventSeats \
    --key "{\"eventId\":{\"S\":\"$1\"}}" \
    --update-expression "SET seatsAvailable = :n" \
    --expression-attribute-values "{\":n\":{\"N\":\"$2\"}}" >/dev/null
  echo "  event $1 -> $2 seats"
}

echo "resetting seats:"
seat 1 2
seat 2 50
seat 3 0

