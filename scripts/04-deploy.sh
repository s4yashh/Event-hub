#!/usr/bin/env bash
# =============================================================================
# EventHub build — STEP 4: deploy the web app to EC2
#   * waits for RDS to become available, stores /eventhub/db-host
#   * copies app/ to the instance, runs setup.sh (venv + systemd + start)
#   * loads schema.sql + seed.sql + seed-extra.sql into RDS (credentials fetched on the
#     instance via its IAM role — no passwords travel through this script)
#   * verifies the web app answers on port 80
# Run: bash scripts/04-deploy.sh
# =============================================================================
set -euo pipefail

REGION="${REGION:-ap-south-1}"
export AWS_DEFAULT_REGION="$REGION"
export AWS_PAGER=""
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="$SCRIPT_DIR/state.env"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KEY_FILE="$PROJECT_DIR/eventhub-key.pem"
# shellcheck disable=SC1090
source "$STATE"

SSH_OPTS=(-i "$KEY_FILE" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8)

echo "== EventHub deploy =="

# ---- 0. wait for RDS + store db-host ---------------------------------------
if aws ssm get-parameter --name /eventhub/db-host >/dev/null 2>&1; then
  echo "[0/4] db-host parameter already exists"
else
  echo "[0/4] waiting for RDS eventhub-mysql to become available (can take ~10 min)..."
  aws rds wait db-instance-available --db-instance-identifier eventhub-mysql
  DB_HOST=$(aws rds describe-db-instances --db-instance-identifier eventhub-mysql \
    --query 'DBInstances[0].Endpoint.Address' --output text)
  aws ssm put-parameter --name /eventhub/db-host --type String --value "$DB_HOST" --overwrite >/dev/null
  echo "      db-host stored: $DB_HOST"
fi

# ---- 1. wait for SSH --------------------------------------------------------
echo "[1/4] waiting for SSH on ec2-user@$EC2_IP ..."
REACHED=0
for _ in $(seq 1 40); do
  if ssh "${SSH_OPTS[@]}" "ec2-user@$EC2_IP" true 2>/dev/null; then REACHED=1; break; fi
  sleep 5
done
if [ "$REACHED" != "1" ]; then
  echo "!! SSH not reachable. Check that eventhub-web-sg allows TCP 22 from your current public IP."
  exit 1
fi
echo "      SSH OK"

# ---- 2. copy app + bootstrap the instance ----------------------------------
echo "[2/4] copying app to the instance and running setup.sh ..."
ssh "${SSH_OPTS[@]}" "ec2-user@$EC2_IP" 'mkdir -p /home/ec2-user/eventhub-app'
scp "${SSH_OPTS[@]}" -r "$PROJECT_DIR/app/." "ec2-user@$EC2_IP:/home/ec2-user/eventhub-app/"
ssh "${SSH_OPTS[@]}" "ec2-user@$EC2_IP" 'sudo bash /home/ec2-user/eventhub-app/setup.sh'

# ---- 3. load schema + seed (on the instance, using its IAM role) -----------
echo "[3/4] loading schema + seed into RDS ..."
ssh "${SSH_OPTS[@]}" "ec2-user@$EC2_IP" 'bash -s' <<'REMOTE'
set -e
DBHOST=$(aws ssm get-parameter --name /eventhub/db-host --query Parameter.Value --output text)
DBUSER=$(aws ssm get-parameter --name /eventhub/db-user --query Parameter.Value --output text)
DBNAME=$(aws ssm get-parameter --name /eventhub/db-name --query Parameter.Value --output text)
DBPASS=$(aws ssm get-parameter --name /eventhub/db-password --with-decryption --query Parameter.Value --output text)
MYSQL=$(command -v mysql || command -v mariadb)
export MYSQL_PWD="$DBPASS"
$MYSQL -h "$DBHOST" -u "$DBUSER" "$DBNAME" < /opt/eventhub/schema.sql
COUNT=$($MYSQL -h "$DBHOST" -u "$DBUSER" "$DBNAME" -Nse "SELECT COUNT(*) FROM events")
if [ "$COUNT" = "0" ]; then
  $MYSQL -h "$DBHOST" -u "$DBUSER" "$DBNAME" < /opt/eventhub/seed.sql
fi
$MYSQL -h "$DBHOST" -u "$DBUSER" "$DBNAME" < /opt/eventhub/seed-extra.sql
NEW_EVENTS=$($MYSQL -h "$DBHOST" -u "$DBUSER" "$DBNAME" -Nse \
  "SELECT COUNT(*) FROM events WHERE \
   (id=4 AND title='UI/UX Design Sprint') OR \
   (id=5 AND title='Stargazing Night') OR \
   (id=6 AND title='Robotics Build Lab') OR \
   (id=7 AND title='Startup Pitch Arena') OR \
   (id=8 AND title='Python for Data Science') OR \
   (id=9 AND title='Battle of the Bands') OR \
   (id=10 AND title='Cybersecurity CTF Finals') OR \
   (id=11 AND title='Campus Photography Walk') OR \
   (id=12 AND title='Poetry Open Mic')")
if [ "$NEW_EVENTS" != "9" ]; then
  echo "!! Expected nine additional events in RDS, found $NEW_EVENTS. Check for ID or title conflicts." >&2
  exit 1
fi
echo "      events table now:"
$MYSQL -h "$DBHOST" -u "$DBUSER" "$DBNAME" -e "SELECT id, title FROM events"
REMOTE

# Keep existing live seat counts intact; initialize only the new event IDs.
echo "      ensuring DynamoDB seat records for the nine additional events ..."
for spec in '4 36' '5 60' '6 24' '7 80' '8 45' '9 150' '10 1' '11 30' '12 0'; do
  read -r event_id capacity <<< "$spec"
  current=$(aws dynamodb update-item --table-name EventSeats \
    --key "{\"eventId\":{\"S\":\"$event_id\"}}" \
    --update-expression 'SET seatsAvailable = if_not_exists(seatsAvailable, :capacity)' \
    --expression-attribute-values "{\":capacity\":{\"N\":\"$capacity\"}}" \
    --return-values ALL_NEW --query 'Attributes.seatsAvailable.N' --output text)
  echo "      event $event_id: $current seats left"
done

# ---- 4. verify web ----------------------------------------------------------
sleep 3
CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$EC2_IP/")
echo "[4/4] web app HTTP status: $CODE (200 = landing page is healthy)"
if [ "$CODE" != "200" ]; then
  echo "!! The website did not return its landing page. Check: sudo journalctl -u eventhub -n 50 --no-pager"
  exit 1
fi
echo
cat <<DONE
============================================================
DEPLOY DONE
Website: http://$EC2_IP/
(Open it in a browser to see the landing page)
============================================================
DONE
