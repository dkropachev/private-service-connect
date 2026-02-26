#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"

# Validate all required env vars upfront
: "${SCYLLA_API_TOKEN:?Set SCYLLA_API_TOKEN}"
: "${GCP_PROJECT_ID:?Set GCP_PROJECT_ID}"

# Export so child scripts inherit
export SCYLLA_API_TOKEN GCP_PROJECT_ID
export REGION="${REGION:-us-east1}"
export ZONE="${ZONE:-us-east1-b}"
export PORT_BASE="${PORT_BASE:-9001}"
export CQL_PORT_BASE="${CQL_PORT_BASE:-${PORT_BASE}}"
export SSL_CQL_PORT_BASE="${SSL_CQL_PORT_BASE:-$(( ${CQL_PORT_BASE} + 100 ))}"

"$SCRIPT_DIR/01-cluster.sh"
"$SCRIPT_DIR/02-producer-psc.sh"
"$SCRIPT_DIR/03-loader.sh"
"$SCRIPT_DIR/04-psc-connect.sh"

# Final summary
cd "$TF_DIR/03-loader"
LOADER_VM_NAME=$(terraform output -raw loader_vm_name)
LOADER_VM_ZONE=$(terraform output -raw loader_vm_zone)

cd "$TF_DIR/04-psc-connect"
PSC_ENDPOINT_IP=$(terraform output -raw psc_endpoint_ip)
PORT_MAPPING=$(terraform output -json port_mapping)

echo ""
echo "========================================="
echo "  Deployment complete!"
echo "========================================="
echo "PSC Endpoint IP:  $PSC_ENDPOINT_IP"
echo "Loader VM:        $LOADER_VM_NAME ($LOADER_VM_ZONE)"
echo ""
echo "Port mapping (PSC_VIP:port -> node:9042):"
echo "$PORT_MAPPING" | jq -r 'to_entries[] | "  \(.key) -> \(.value)"'
echo ""
echo "Run benchmark:"
echo "  ./scripts/run-latte.sh"
