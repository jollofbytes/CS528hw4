#!/bin/bash
# Runs as root every time the web-server VM boots (attached by deploy.sh).
# Installs Python packages, pulls the server code + settings out of VM metadata,
# and runs the server as a systemd service (auto-restarts if it crashes).
set -e

APP_DIR=/opt/hw4-server
MD=http://metadata.google.internal/computeMetadata/v1
md()   { curl -sf -H "Metadata-Flavor: Google" "$MD/$1"; }
attr() { md "instance/attributes/$1"; }

PROJECT_ID=$(md project/project-id)
BUCKET=$(attr bucket-name || echo cs528hww2)
TOPIC=$(attr topic-id || echo forbidden-requests)

# 1. Python + packages (Debian blocks system-wide pip, so use a virtual env)
apt-get update -y
apt-get install -y python3-venv
mkdir -p "$APP_DIR"
python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install -q google-cloud-storage google-cloud-pubsub google-cloud-logging

# 2. The server code that deploy.sh attached to the VM
attr server-code > "$APP_DIR/main.py"

# 3. Run it as a service
cat > /etc/systemd/system/hw4-server.service <<EOF
[Unit]
Description=CS528 HW4 file server
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/venv/bin/python3 $APP_DIR/main.py
Environment=BUCKET_NAME=$BUCKET
Environment=PROJECT_ID=$PROJECT_ID
Environment=TOPIC_ID=$TOPIC
Environment=PORT=80
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hw4-server
systemctl restart hw4-server
