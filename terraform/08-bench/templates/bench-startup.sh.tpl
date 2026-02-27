#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y dnsutils

FQDN="${psc_endpoint_name}.${dns_domain}"

echo "=== DNS resolution ==="
dig A "$FQDN" +short
echo ""

echo "=== CQL port connectivity ==="
%{ for port in cql_ports ~}
if timeout 5 bash -c "exec 3<>/dev/tcp/$FQDN/${port}" 2>/dev/null; then
  echo "$FQDN:${port} OPEN"
else
  echo "$FQDN:${port} CLOSED"
fi
%{ endfor ~}

echo ""
echo "done" > /opt/bench-test.done
