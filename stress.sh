#!/bin/bash
# Stress test: runs N copies of the http-client at the same time, for DURATION seconds,
# then counts the responses each client got.
# Run it ON the client VM from your Mac with:
#   gcloud compute ssh hw4-client --zone=us-central1-a --command "bash -s 2" < stress.sh
# (the number after -s is how many clients; optional 2nd number = seconds, default 180)

N=${1:-1}
DURATION=${2:-180}
SERVER=104.198.201.20

mkdir -p ~/stress && cd ~/stress && rm -f client*.log
echo "Starting $N client(s) for $DURATION s at $(date -u +%H:%M:%S) UTC"

for i in $(seq 1 "$N"); do
  # -n is huge so each client keeps going until `timeout` stops it.
  # Keep only status lines and anything that looks like a failure.
  ( timeout "$DURATION" http-client -d $SERVER -p 80 -b none -w CS528-HW_2-output-x2Yenv \
        -n 1000000 -i 10000 -r $RANDOM -v 2>&1 \
      | grep -aE '^[0-9]{3} |Timeout|Error|Traceback' > client$i.log ) &
done
wait

echo "Finished at $(date -u +%H:%M:%S) UTC"
for i in $(seq 1 "$N"); do
  echo "-- client $i"
  sort client$i.log | uniq -c | sort -rn | head
done
echo "-- all clients combined"
cat client*.log | sort | uniq -c | sort -rn | head
