#!/bin/bash
# Creates the HW4 web server VM. Run from the folder with HW4.py and startup-server.sh:
#   bash setup-server.sh
# Safe to rerun: steps that already happened just print "already exists".

PROJECT=solar-attic-508721-n0
REGION=us-central1
ZONE=us-central1-a
SA=hw4-server-sa@$PROJECT.iam.gserviceaccount.com

echo "== Project + Compute API =="
gcloud config set project $PROJECT
gcloud services enable compute.googleapis.com

echo "== Service account + least-privilege permissions =="
gcloud iam service-accounts create hw4-server-sa
sleep 10  # give the new service account a moment to exist everywhere
gcloud storage buckets add-iam-policy-binding gs://cs528hww2 --member=serviceAccount:$SA --role=roles/storage.objectViewer
gcloud pubsub topics add-iam-policy-binding forbidden-requests --member=serviceAccount:$SA --role=roles/pubsub.publisher
gcloud projects add-iam-policy-binding $PROJECT --member=serviceAccount:$SA --role=roles/logging.logWriter --condition=None

echo "== Static IP + firewall =="
gcloud compute addresses create hw4-server-ip --region=$REGION
IP=$(gcloud compute addresses describe hw4-server-ip --region=$REGION --format='value(address)')
gcloud compute firewall-rules create hw4-allow-http --allow=tcp:80 --target-tags=hw4-server

echo "== Create the VM (starts it + runs the startup script) =="
gcloud compute instances create hw4-server --zone=$ZONE \
  --machine-type=e2-micro --image-family=debian-12 --image-project=debian-cloud \
  --address=$IP --tags=hw4-server --service-account=$SA --scopes=cloud-platform \
  --metadata-from-file=startup-script=startup-server.sh,server-code=HW4.py

echo ""
echo "Server IP: $IP"
echo "Wait ~2 minutes, then test:  curl http://$IP/CS528-HW_2-output-x2Yenv/1.html"
