#!/bin/bash
# Runs as root every time the forbidden-service VM boots.
# Installs Python packages, pulls the code out of VM metadata, runs it as a systemd service.
set -e

APP_DIR=/opt/hw4-forbidden
META=http://metadata.google.internal/computeMetadata/v1/instance/attributes

apt-get update -y
apt-get install -y python3-venv
mkdir -p "$APP_DIR"
python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install -q google-cloud-pubsub

curl -sf -H "Metadata-Flavor: Google" "$META/forbidden-code" -o "$APP_DIR/forbidden_service.py"

cat > /etc/systemd/system/hw4-forbidden.service <<EOF
[Unit]
Description=CS528 HW4 forbidden-country reporter
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/venv/bin/python3 $APP_DIR/forbidden_service.py
Environment=PROJECT_ID=solar-attic-508721-n0
Environment=SUBSCRIPTION_ID=forbidden-requests-sub
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
