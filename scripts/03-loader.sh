#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"

: "${GCP_PROJECT_ID:?Set GCP_PROJECT_ID}"

REGION="${REGION:-us-east1}"
ZONE="${ZONE:-us-east1-b}"
PORT_BASE="${PORT_BASE:-9001}"

# Read from stage 01
cd "$TF_DIR/01-cluster"
NODE_IPS_JSON=$(terraform output -json node_private_ips)
CQL_USERNAME=$(terraform output -raw cql_username)
CQL_PASSWORD=$(terraform output -raw cql_password)

echo "=== Stage 03: Loader Infrastructure ==="
cd "$TF_DIR/03-loader"
terraform init -input=false
terraform apply -input=false -auto-approve \
  -var="gcp_project_id=${GCP_PROJECT_ID}" \
  -var="region=${REGION}" \
  -var="zone=${ZONE}" \
  -var="cql_username=${CQL_USERNAME}" \
  -var="cql_password=${CQL_PASSWORD}" \
  -var="port_base=${PORT_BASE}" \
  -var="node_private_ips=${NODE_IPS_JSON}"

LOADER_VM_NAME=$(terraform output -raw loader_vm_name)
LOADER_VM_ZONE=$(terraform output -raw loader_vm_zone)

echo ""
echo "Loader VM: $LOADER_VM_NAME ($LOADER_VM_ZONE)"
