#!/bin/bash
# EventHub bootstrap — run ON the EC2 instance after copying the app folder:
#   scp -i eventhub-key.pem -r app/ ec2-user@<EC2-public-IP>:~/eventhub-app
#   ssh -i eventhub-key.pem ec2-user@<EC2-public-IP>
#   sudo bash ~/eventhub-app/setup.sh
#
# What it does (idempotent — safe to re-run):
#   1. installs python + mysql client
#   2. copies the app to /opt/eventhub and builds a virtualenv
#   3. installs both systemd units and starts the web app
#      (the worker is started later, in Phase 5, once its queue and state
#       machine exist — it would just crash-loop before that)
set -euo pipefail

APP_SRC="$(cd "$(dirname "$0")" && pwd)"
APP_DIR=/opt/eventhub

echo "==> Installing packages (python3-pip, mysql client)"
sudo dnf install -y python3-pip mariadb105

echo "==> Copying app to ${APP_DIR}"
sudo mkdir -p "${APP_DIR}"
sudo cp -r "${APP_SRC}/." "${APP_DIR}/"
sudo chown -R ec2-user:ec2-user "${APP_DIR}"

echo "==> Creating virtualenv and installing requirements"
cd "${APP_DIR}"
if [ ! -d venv ]; then
  python3 -m venv venv
fi
./venv/bin/pip install --upgrade pip -q
./venv/bin/pip install -r requirements.txt -q

echo "==> Installing systemd units"
sudo cp "${APP_DIR}/eventhub.service" /etc/systemd/system/
sudo cp "${APP_DIR}/worker.service"   /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable eventhub
sudo systemctl enable worker

echo "==> Starting the web app (worker starts in Phase 5)"
sudo systemctl restart eventhub

echo
echo "Done. Check with:  sudo systemctl status eventhub"
echo "Then open:         http://<EC2-public-IP>/  (port 80)"
echo "Logs:              journalctl -u eventhub -f"
