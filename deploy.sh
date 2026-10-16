#!/bin/bash
# CS528 HW4 - one-command deployment.
#
#   bash deploy.sh              create everything and start both services
#   bash deploy.sh client       also create the client VM (runs the course http-client)
#   bash deploy.sh delete       delete all HW4 VMs (keeps IP, firewall, service accounts)
#   bash deploy.sh delete-all   delete the VMs AND the static IP, firewall rule, service accounts
#
# Settings can be changed without editing the file, e.g.
#   PROJECT_ID=my-project BUCKET=my-bucket bash deploy.sh
#
# Needs: gcloud installed and logged in (`gcloud auth login`) as a project Owner/Editor,
# and an existing bucket holding the HW2 files. Everything else is created here.

PROJECT_ID=${PROJECT_ID:-solar-attic-508721-n0}
BUCKET=${BUCKET:-cs528hww2}
TOPIC=${TOPIC:-forbidden-requests}
SUBSCRIPTION=${SUBSCRIPTION:-forbidden-requests-sub}
REGION=${REGION:-us-central1}
ZONE=${ZONE:-us-central1-a}

SERVER_SA=hw4-server-sa@$PROJECT_ID.iam.gserviceaccount.com
FORBIDDEN_SA=hw4-forbidden-sa@$PROJECT_ID.iam.gserviceaccount.com

cd "$(dirname "$0")"                      # so the code files next to this script are found
gcloud config set project "$PROJECT_ID" --quiet

exists() { "$@" >/dev/null 2>&1; }        # true if a `describe` command succeeds
step()   { echo; echo "== $* =="; }

delete_vms() {
  step "Deleting VMs"
  for vm in hw4-server hw4-forbidden hw4-client; do
    if exists gcloud compute instances describe $vm --zone=$ZONE; then
      gcloud compute instances delete $vm --zone=$ZONE --quiet
    fi
  done
}

case "${1:-deploy}" in
  delete)
    delete_vms; exit 0 ;;
  delete-all)
    delete_vms
    step "Deleting static IP, firewall rule, service accounts"
    exists gcloud compute addresses describe hw4-server-ip --region=$REGION && \
      gcloud compute addresses delete hw4-server-ip --region=$REGION --quiet
    exists gcloud compute firewall-rules describe hw4-allow-http && \
      gcloud compute firewall-rules delete hw4-allow-http --quiet
    for sa in $SERVER_SA $FORBIDDEN_SA; do
      exists gcloud iam service-accounts describe $sa && gcloud iam service-accounts delete $sa --quiet
    done
    exit 0 ;;
  deploy|client) ;;
  *) echo "Unknown option '$1'. Use: deploy | client | delete | delete-all"; exit 1 ;;
esac

step "Enabling APIs"
gcloud services enable compute.googleapis.com pubsub.googleapis.com logging.googleapis.com

step "Pub/Sub topic + subscription (Service 1 -> Service 2)"
exists gcloud pubsub topics describe $TOPIC || gcloud pubsub topics create $TOPIC
exists gcloud pubsub subscriptions describe $SUBSCRIPTION || \
  gcloud pubsub subscriptions create $SUBSCRIPTION --topic=$TOPIC

step "Service accounts"
for name in hw4-server-sa hw4-forbidden-sa; do
  exists gcloud iam service-accounts describe $name@$PROJECT_ID.iam.gserviceaccount.com || {
    gcloud iam service-accounts create $name
    sleep 10   # new accounts take a moment before they can be granted roles
  }
done

step "Least-privilege permissions"
# Web server: read the bucket, publish forbidden requests, write logs. Nothing else.
gcloud storage buckets add-iam-policy-binding gs://$BUCKET \
  --member=serviceAccount:$SERVER_SA --role=roles/storage.objectViewer >/dev/null
gcloud pubsub topics add-iam-policy-binding $TOPIC \
  --member=serviceAccount:$SERVER_SA --role=roles/pubsub.publisher >/dev/null
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member=serviceAccount:$SERVER_SA --role=roles/logging.logWriter --condition=None >/dev/null
# Forbidden service: only read from its subscription.
gcloud pubsub subscriptions add-iam-policy-binding $SUBSCRIPTION \
  --member=serviceAccount:$FORBIDDEN_SA --role=roles/pubsub.subscriber >/dev/null
echo "done"

step "Static IP + firewall (port 80)"
exists gcloud compute addresses describe hw4-server-ip --region=$REGION || \
  gcloud compute addresses create hw4-server-ip --region=$REGION
IP=$(gcloud compute addresses describe hw4-server-ip --region=$REGION --format='value(address)')
exists gcloud compute firewall-rules describe hw4-allow-http || \
  gcloud compute firewall-rules create hw4-allow-http --allow=tcp:80 --target-tags=hw4-server

step "Web server VM (starts the server automatically)"
if exists gcloud compute instances describe hw4-server --zone=$ZONE; then
  echo "hw4-server already exists"
else
  gcloud compute instances create hw4-server --zone=$ZONE \
    --machine-type=e2-micro --image-family=debian-12 --image-project=debian-cloud \
    --address=$IP --tags=hw4-server \
    --service-account=$SERVER_SA --scopes=cloud-platform \
    --metadata=bucket-name=$BUCKET,topic-id=$TOPIC \
    --metadata-from-file=startup-script=startup-server.sh,server-code=HW4.py
fi

step "Forbidden-country VM (starts Service 2 automatically)"
if exists gcloud compute instances describe hw4-forbidden --zone=$ZONE; then
  echo "hw4-forbidden already exists"
else
  gcloud compute instances create hw4-forbidden --zone=$ZONE \
    --machine-type=e2-micro --image-family=debian-12 --image-project=debian-cloud \
    --service-account=$FORBIDDEN_SA --scopes=cloud-platform \
    --metadata=subscription-id=$SUBSCRIPTION \
    --metadata-from-file=startup-script=startup-forbidden.sh,forbidden-code=forbidden_service.py
fi

if [ "${1:-deploy}" = client ]; then
  step "Client VM (no service account: it only sends HTTP requests)"
  if exists gcloud compute instances describe hw4-client --zone=$ZONE; then
    echo "hw4-client already exists"
  else
    gcloud compute instances create hw4-client --zone=$ZONE \
      --machine-type=e2-small --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud \
      --no-service-account --no-scopes \
      --metadata-from-file=startup-script=startup-client.sh,client-code=http-client.pyc.b64
  fi
fi

cat <<EOF

Done. Both services start on their own in ~2-3 minutes.
  Server:      http://$IP/
  Test:        curl http://$IP/CS528-HW_2-output-x2Yenv/1.html
  Forbidden:   curl -H "X-country: Iran" http://$IP/CS528-HW_2-output-x2Yenv/1.html
  Service 2:   gcloud compute instances get-serial-port-output hw4-forbidden --zone=$ZONE | grep FORBIDDEN
  Clean up:    bash deploy.sh delete
EOF
