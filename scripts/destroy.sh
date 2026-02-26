#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"

: "${GCP_PROJECT_ID:?Set GCP_PROJECT_ID}"

REGION="${REGION:-us-east1}"
ZONE="${ZONE:-us-east1-b}"

echo "=== Destroying in reverse order ==="

echo "=== Stage 04: PSC Connection ==="
cd "$TF_DIR/04-psc-connect"
if [ -d .terraform ]; then
  terraform destroy -input=false -auto-approve \
    -var="gcp_project_id=${GCP_PROJECT_ID}" \
    -var="region=${REGION}" \
    -var="service_attachment_self_link=placeholder" \
    -var="consumer_vpc_id=placeholder" \
    -var="consumer_subnet_id=placeholder" \
    -var='node_private_ips=[]' \
    || echo "Stage 04 destroy failed or already clean"
fi

echo "=== Stage 03: Loader Infrastructure ==="
cd "$TF_DIR/03-loader"
if [ -d .terraform ]; then
  terraform destroy -input=false -auto-approve \
    -var="gcp_project_id=${GCP_PROJECT_ID}" \
    -var="region=${REGION}" \
    -var="zone=${ZONE}" \
    -var="cql_username=placeholder" \
    -var="cql_password=placeholder" \
    -var='node_private_ips=[]' \
    || echo "Stage 03 destroy failed or already clean"
fi

echo "=== Stage 02: Producer PSC ==="
cd "$TF_DIR/02-producer-psc"
if [ -d .terraform ]; then
  terraform destroy -input=false -auto-approve \
    -var="gcp_project_id=${GCP_PROJECT_ID}" \
    -var="region=${REGION}" \
    -var="scylla_vpc_name=placeholder" \
    -var="scylla_subnet_name=placeholder" \
    -var='node_instances=[]' \
    || echo "Stage 02 destroy failed or already clean"
fi

echo "=== Stage 01: ScyllaDB Cluster ==="
cd "$TF_DIR/01-cluster"
if [ -d .terraform ]; then
  terraform destroy -input=false -auto-approve \
    -var="region=${REGION}" \
    || echo "Stage 01 destroy failed or already clean"
fi

echo ""
echo "=== Destroy complete ==="
