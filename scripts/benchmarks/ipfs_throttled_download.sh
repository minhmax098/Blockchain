#!/usr/bin/env bash
# Measures download time of an IPFS object through the local Kubo gateway at limited client bandwidth.
# Models T = Size / Bandwidth (+ overhead). It does NOT model P2P discovery, latency or packet loss.
# Usage: ./ipfs_throttled_download.sh [SIZE_MB]      (default 1024)

set -euo pipefail
SIZE_MB="${1:-1024}"
API="${IPFS_API:-http://127.0.0.1:5001}"
GW="${IPFS_GW:-http://127.0.0.1:8080}"

head -c "$((SIZE_MB*1024*1024))" /dev/urandom > payload.bin
CID=$(curl -s -X POST -F file=@payload.bin "$API/api/v0/add?pin=true&quieter=true" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read().strip().splitlines()[-1])["Hash"])')
echo "CID=$CID size=${SIZE_MB}MB"
echo "mbps,seconds,model_seconds"

for MBPS in 10 50 100 500; do
    RATE=$(( MBPS * 125000 ))    # bytes/s
    S=$(curl -s -o /dev/null -w '%{time_total}' --limit-rate "$RATE" "$GW/ipfs/$CID")
    M=$(python3 -c "print(round($SIZE_MB*8/$MBPS,1))")
    echo "$MBPS,$S,$M"
done
rm -f payload.bin
