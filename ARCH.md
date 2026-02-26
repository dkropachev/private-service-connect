
# Scylla + GCP Private Service Connect (PSC) Port Mapping Architecture

## Goal

- Scylla cluster spans multiple regions.
- Each **region = DC**, each **zone = rack**.
- Clients connect via **GCP Private Service Connect (PSC)**.
- Clients must be able to reach **each individual Scylla node**.
- Use **one PSC VIP per region/DC**, with **port-based routing to nodes**.
- Avoid public networking and external NAT.

---

## High-Level Architecture (Per Region / DC)

### Producer Side (ScyllaDB VPC)

The PSC producer infrastructure lives in the same VPC as ScyllaDB nodes. This is what ScyllaDB Cloud would provide natively.

Components:

- Scylla nodes (VMs) distributed across zones
- **Port Mapping NEG** mapping client ports to node VMs
- Internal Load Balancer (ILB) fronting the NEG
- PSC **Service Attachment** publishing the ILB
- PSC NAT subnet for address translation
- Firewall rules allowing health check and PSC traffic

### Consumer Side (Client VPC)

Components:

- Single **PSC Endpoint VIP** per region/DC
- Clients connect using `VIP:port` where each port maps to a specific node

---

## Textual Flow Diagram

```
Consumer VPC (Clients)
----------------------

Application / Driver
    |
    | Connect to:
    |   PSC_VIP:10001  -> node1:9042
    |   PSC_VIP:10002  -> node2:9042
    |   PSC_VIP:10003  -> node3:9042
    v
[PSC Endpoint VIP]
        |
        v  (Private Service Connect)
        |
Producer VPC (ScyllaDB)
-----------------------

[PSC Service Attachment]
        |
        v
[Internal Load Balancer (all ports)]
        |
        v
[Port Mapping NEG]
        |
        +-- 10001 -> node1 VM : 9042
        +-- 10002 -> node2 VM : 9042
        +-- 10003 -> node3 VM : 9042
        |
        v
    Scylla Nodes
```

PSC port mapping forwards traffic based on **destination port**, not load balancing. Each port maps to a specific VM and service port. No intermediate proxies.

---

## Port Allocation Strategy

Deterministic scheme:

- Region A: ports `10000–19999`
- Region B: ports `20000–29999`

Per node:

```
client_port = port_base + node_index
destination = node_ip:9042
```

Optional:

- Reserve extra ports for TLS (`9142`)
- Allocate two ports per node if exposing multiple services

---

## Producer-Side Setup

1. Create **PSC NAT Subnet** in ScyllaDB VPC
   - Purpose: PRIVATE_SERVICE_CONNECT

2. Create **Port Mapping NEG**
   - Type: GCE_VM_PORT_MAPPING
   - Add each Scylla VM as an endpoint
   - Map client port -> VM instance : 9042

3. Create **Internal Load Balancer**
   - Backend service pointing to Port Mapping NEG
   - Forwarding rule with `all_ports = true`

4. Create **PSC Service Attachment**
   - Publish the ILB via Private Service Connect
   - Use PSC NAT subnet for address translation

5. Configure **Firewall Rules**
   - Allow health check probes to port 9042
   - Allow PSC NAT traffic to port 9042

---

## Consumer-Side Setup

1. Create **Consumer VPC** with subnet

2. Create **PSC Endpoint**
   - Single VIP per region/DC
   - Points to the PSC Service Attachment

3. DNS (optional)

```
psc-scylla-dc1.internal -> PSC VIP
```

4. Clients connect using:

```
psc-scylla-dc1.internal:<node_port>
```

---

## Driver Address Translation (Critical)

Scylla drivers discover nodes using internal IPs. Those IPs are not reachable via PSC.

You must implement **address translation**:

```
node_private_ip:9042
        ↓
PSC_VIP:node_port
```

Recommended mapping key:

- Scylla `host_id` (stable)
- Instance metadata or node identity

Implement translation in:

- Driver address translator hooks
- Custom resolver library
- Sidecar mapping service

---

## Multi-Region Strategy

Repeat architecture per region:

- One PSC service per DC
- One PSC VIP per DC in consumer VPC

Clients:

- Prefer local region VIP
- Optionally access remote DCs

---

## Automation Requirements

You need automation that:

- Updates port mappings when nodes change
- Reconfigures NEG entries
- Publishes updated mapping to clients
- Keeps translation tables synchronized

Recommended tools:

- Terraform / Pulumi
- GCP API automation
- Cluster lifecycle hooks

---

## Summary

This architecture provides:

- One PSC VIP per region
- Direct per-node connectivity via native GCP port mapping
- No public exposure
- No intermediate proxies
- Deterministic routing
- Scalable multi-DC topology

Key tradeoff:

- Requires address translation and lifecycle automation
