#!/bin/bash
# Runs as root every time the server VM boots.
# It installs Python packages, pulls main.py out of the VM's metadata,
# and runs it as a systemd service (auto-restarts if it crashes).
set -e

APP_DIR=/opt/hw4-server
META=http://metadata.google.internal/computeMetadata/v1/instance/attributes

# 1. Python + packages (Debian blocks system-wide pip, so use a virtual env)
apt-get update -y
apt-get install -y python3-venv
mkdir -p "$APP_DIR"
python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install -q google-cloud-storage google-cloud-pubsub google-cloud-logging

# 2. Get the server code that was attached to the VM at creation (--metadata-from-file)
curl -sf -H "Metadata-Flavor: Google" "$META/server-code" -o "$APP_DIR/main.py"

# 3. Run it as a service
cat > /etc/systemd/system/hw4-server.service <<EOF
[Unit]
Description=CS528 HW4 file server
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/venv/bin/python3 $APP_DIR/main.py
Environment=BUCKET_NAME=cs528hww2
Environment=PROJECT_ID=solar-attic-508721-n0
Environment=TOPIC_ID=forbidden-requests
Environment=PORT=80
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hw4-server
systemctl restart hw4-server
