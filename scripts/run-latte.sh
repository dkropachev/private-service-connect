#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"

: "${GCP_PROJECT_ID:?Set GCP_PROJECT_ID}"

# Read loader VM info from stage 03
cd "$TF_DIR/03-loader"
LOADER_VM_NAME=$(terraform output -raw loader_vm_name)
LOADER_VM_ZONE=$(terraform output -raw loader_vm_zone)

# Read port mapping from stage 04
cd "$TF_DIR/04-psc-connect"
PORT_MAPPING=$(terraform output -json port_mapping 2>/dev/null || echo "{}")

# Configurable benchmark parameters
DURATION="${LATTE_DURATION:-60s}"
RATE="${LATTE_RATE:-1000}"
CONNECTIONS="${LATTE_CONNECTIONS:-4}"

echo "Loader VM:    $LOADER_VM_NAME ($LOADER_VM_ZONE)"
echo "Duration:     $DURATION"
echo "Rate:         $RATE ops/s"
echo "Connections:  $CONNECTIONS"
echo ""

if [ "$PORT_MAPPING" != "{}" ]; then
  echo "Port mapping:"
  echo "$PORT_MAPPING" | jq -r 'to_entries[] | "  \(.key) -> \(.value)"'
  echo ""
fi

REMOTE_CMD=$(cat <<'REMOTEOF'
set -euo pipefail
source /opt/latte/env.sh

DURATION="${1:-60s}"
RATE="${2:-1000}"
CONNECTIONS="${3:-4}"

LATTE="docker run --rm --network host -v /opt/latte:/workdir scylladb/latte:latest"

echo "Connecting to: $PSC_ENDPOINT"
echo ""

echo "=== Creating schema ==="
$LATTE schema \
  --user "$CQL_USERNAME" --password "$CQL_PASSWORD" \
  /workdir/basic_read_write.rn "$PSC_ENDPOINT"

echo "=== Running write workload ==="
$LATTE run \
  --user "$CQL_USERNAME" --password "$CQL_PASSWORD" \
  --duration "$DURATION" --rate "$RATE" --connections "$CONNECTIONS" \
  --function write \
  /workdir/basic_read_write.rn "$PSC_ENDPOINT"

echo "=== Running read workload ==="
$LATTE run \
  --user "$CQL_USERNAME" --password "$CQL_PASSWORD" \
  --duration "$DURATION" --rate "$RATE" --connections "$CONNECTIONS" \
  --function read \
  /workdir/basic_read_write.rn "$PSC_ENDPOINT"
REMOTEOF
)

gcloud compute ssh "$LOADER_VM_NAME" \
  --zone="$LOADER_VM_ZONE" \
  --project="$GCP_PROJECT_ID" \
  --tunnel-through-iap \
  -- bash -c "$REMOTE_CMD" -- "$DURATION" "$RATE" "$CONNECTIONS"
