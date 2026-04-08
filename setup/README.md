# Setup — EC2 Monitoring Stack

This directory provisions and configures the EC2 instance that runs the demo workload (httpd) and the monitoring stack (Prometheus, AlertManager, Node Exporter) that detects outages and creates ServiceNow incidents.

You only need to run this **once** before the demo.

## Prerequisites

- AWS CLI configured with valid credentials
- Terraform >= 1.5
- Ansible (any recent version with `ansible.builtin` modules)
- An existing EC2 key pair in your target AWS region
- ServiceNow credentials in the root `.env` file

## 1. Provision the EC2 Instance

```bash
cd setup/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set key_name, private_key_path, and optionally allowed_cidr
terraform init
terraform apply
```

Terraform will output the public IP and auto-generate `setup/playbooks/inventory/hosts.yml`.

## 2. Configure the Monitoring Stack

```bash
# From the repo root
source .env
ansible-playbook -i setup/playbooks/inventory/hosts.yml setup/playbooks/setup_monitoring_stack.yml
```

This installs and starts all five systemd services on the EC2 instance:

| Service | Port | Role |
|---------|------|------|
| httpd | 80 | Hello-world app (the monitored workload) |
| node_exporter | 9100 | Exposes systemd unit metrics |
| prometheus | 9090 | Scrapes node_exporter, evaluates alert rules |
| alertmanager | 9093 | Routes alerts to the webhook bridge |
| snow-webhook | 5001 | Translates AlertManager alerts into ServiceNow incidents |

## 3. Verify

- **Hello World** — `http://<EC2_IP>`
- **Prometheus Targets** — `http://<EC2_IP>:9090/targets` (both should show UP)
- **AlertManager** — `http://<EC2_IP>:9093`

## What Happens When httpd Stops

1. Node Exporter reports `node_systemd_unit_state{name="httpd.service", state="active"} == 0`
2. Prometheus fires the `ServiceDown_httpd` alert after 15 seconds
3. AlertManager sends a webhook to the local bridge (port 5001)
4. The bridge POSTs a new incident to ServiceNow via the Table API
5. From there, the EDA rulebook and ALIA diagnostics take over (see root README)
