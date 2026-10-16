#!/bin/bash
# Creates the HW4 client VM (runs the course's http-client against the server).
# Run from the folder with startup-client.sh and http-client.pyc.b64:
#   bash setup-client.sh

PROJECT=solar-attic-508721-n0
ZONE=us-central1-a

gcloud config set project $PROJECT

# Ubuntu 24.04 because it ships Python 3.12, the version the client was built with.
# No service account: the client only sends HTTP requests, it needs no Google permissions.
gcloud compute instances create hw4-client --zone=$ZONE \
  --machine-type=e2-small --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud \
  --no-service-account --no-scopes \
  --metadata-from-file=startup-script=startup-client.sh,client-code=http-client.pyc.b64

echo ""
echo "Wait ~2 minutes, then run 100 requests from the client VM:"
echo "  gcloud compute ssh hw4-client --zone=$ZONE --command \"http-client -d 104.198.201.20 -p 80 -b none -w CS528-HW_2-output-x2Yenv -n 100 -i 10000 -v | grep -E '^[0-9]{3} '\""
