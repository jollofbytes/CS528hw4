#!/bin/bash
# Runs as root when the client VM boots.
# Installs the course's http-client (Python 3.12 bytecode pulled out of the Mac
# binary) so it can be run on Linux as the command:  http-client ...
set -e

META=http://metadata.google.internal/computeMetadata/v1/instance/attributes

apt-get update -y
apt-get install -y python3-certifi   # the client's only non-standard dependency

mkdir -p /opt/http-client
curl -sf -H "Metadata-Flavor: Google" "$META/client-code" | base64 -d > /opt/http-client/http-client.pyc

cat > /usr/local/bin/http-client <<'EOF'
#!/bin/bash
exec python3 /opt/http-client/http-client.pyc "$@"
EOF
chmod +x /usr/local/bin/http-client
