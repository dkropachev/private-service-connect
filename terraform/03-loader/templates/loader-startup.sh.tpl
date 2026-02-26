#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Install Docker
apt-get update -y
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io

systemctl enable docker
systemctl start docker

# Pull latte image
docker pull scylladb/latte:latest

# Create working directory
mkdir -p /opt/latte

# Write CQL credentials and port mapping
cat > /opt/latte/env.sh <<'ENVEOF'
export CQL_USERNAME="${cql_username}"
export CQL_PASSWORD="${cql_password}"
export PSC_ENDPOINT="${psc_endpoint_ip}:${port_base}"
# Port mapping: PSC_VIP:port -> node_ip:9042
%{ for idx, ip in node_private_ips ~}
# ${psc_endpoint_ip}:${port_base + idx} -> ${ip}:9042
%{ endfor ~}
ENVEOF
chmod 600 /opt/latte/env.sh

# Write workload file
cat > /opt/latte/basic_read_write.rn <<'RNEOF'
${workload_content}
RNEOF

echo "Loader VM setup complete" > /opt/latte/setup.done
