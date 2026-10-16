#!/bin/bash
# Runs as root every time the forbidden-service VM boots (attached by deploy.sh).
# Installs Python packages, pulls the code + settings out of VM metadata,
# and runs it as a systemd service.
set -e

APP_DIR=/opt/hw4-forbidden
MD=http://metadata.google.internal/computeMetadata/v1
md()   { curl -sf -H "Metadata-Flavor: Google" "$MD/$1"; }
attr() { md "instance/attributes/$1"; }

PROJECT_ID=$(md project/project-id)
SUBSCRIPTION=$(attr subscription-id || echo forbidden-requests-sub)

apt-get update -y
apt-get install -y python3-venv
mkdir -p "$APP_DIR"
python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install -q google-cloud-pubsub

attr forbidden-code > "$APP_DIR/forbidden_service.py"

cat > /etc/systemd/system/hw4-forbidden.service <<EOF
[Unit]
Description=CS528 HW4 forbidden-country reporter
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/venv/bin/python3 $APP_DIR/forbidden_service.py
Environment=PROJECT_ID=$PROJECT_ID
Environment=SUBSCRIPTION_ID=$SUBSCRIPTION
Environment=PYTHONUNBUFFERED=1
# stdout goes to the system log AND the serial console (viewable without SSH)
StandardOutput=journal+console
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hw4-forbidden
systemctl restart hw4-forbidden
