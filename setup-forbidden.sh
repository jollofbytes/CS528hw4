#!/bin/bash
# Creates the HW4 forbidden-country service VM. Run from the folder with
# forbidden_service.py and startup-forbidden.sh:
#   bash setup-forbidden.sh
# Safe to rerun: steps that already happened just print "already exists".

PROJECT=solar-attic-508721-n0
ZONE=us-central1-a
SA=hw4-forbidden-sa@$PROJECT.iam.gserviceaccount.com

gcloud config set project $PROJECT

echo "== Service account: can ONLY read from the forbidden-requests subscription =="
gcloud iam service-accounts create hw4-forbidden-sa
sleep 10
gcloud pubsub subscriptions add-iam-policy-binding forbidden-requests-sub \
  --member=serviceAccount:$SA --role=roles/pubsub.subscriber

echo "== Create the VM (starts it + runs the startup script) =="
gcloud compute instances create hw4-forbidden --zone=$ZONE \
  --machine-type=e2-micro --image-family=debian-12 --image-project=debian-cloud \
  --service-account=$SA --scopes=cloud-platform \
  --metadata-from-file=startup-script=startup-forbidden.sh,forbidden-code=forbidden_service.py

echo ""
echo "Wait ~2 minutes. To see what it prints:"
echo "  gcloud compute instances get-serial-port-output hw4-forbidden --zone=$ZONE | grep -E 'Listening|FORBIDDEN'"
