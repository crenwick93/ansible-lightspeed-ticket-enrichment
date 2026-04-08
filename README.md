# Ansible Lightspeed Ticket Enrichment

Automated incident diagnostics powered by Ansible Lightspeed (ALIA). When a ServiceNow incident is created, Event-Driven Ansible picks it up, runs AI-powered diagnostics, and publishes the results back to the incident — no human intervention required.

## Demo Flow

```
  ServiceNow              EDA Rulebook              AAP Controller
  ┌──────────┐           ┌──────────────┐          ┌──────────────────┐
  │ Incident │<──polled──│ listen_snow  │──launch──>│ ALIA Diagnostics │
  │ created  │  every    │ _incidents   │          │  (Job Template)  │
  └──────────┘  10s      └──────────────┘          └────────┬─────────┘
                                                            │
                                                            │ AI analysis
                                                            ▼
                                                   ┌──────────────────┐
                                                   │ Update incident  │
                                                   │ with worknotes   │
                                                   └──────────────────┘
```

1. A **ServiceNow incident** is created (manually, or via the Prometheus monitoring stack in `setup/`)
2. The **EDA rulebook** polls the incident table every 10 seconds and detects the new record
3. EDA launches the **ALIA Diagnostics** job template on AAP Controller
4. The playbook sends the incident description to the Ansible Lightspeed AI agent
5. Diagnostics results are **posted back** to the ServiceNow incident as worknotes

## Key Files

| File | Purpose |
|------|---------|
| `playbooks/alia_diagnostics.yml` | Calls ALIA for RCA diagnostics, updates the ServiceNow incident |
| `rulebooks/listen_snow_incidents.yml` | EDA rulebook — monitors ServiceNow incident table |
| `ansible_deployment/caac/` | Configuration-as-Code to push all AAP objects (projects, job templates, EDA activations) |

## Running the Demo

### Trigger an incident

SSH into the monitoring EC2 instance and stop the httpd service:

```bash
ssh -i ~/.ssh/your-key.pem ec2-user@<EC2_IP>
sudo systemctl stop httpd
```

Within ~30 seconds, AlertManager will create a ServiceNow incident automatically.

Alternatively, create an incident manually in ServiceNow — the EDA rulebook will pick it up either way.

### What to watch

1. **ServiceNow** — a new incident appears with the alert details
2. **AAP Controller** — the "ALIA Diagnostics" job kicks off automatically
3. **ServiceNow** — the incident is updated to "In Progress" with AI-generated worknotes

### Restore the service

```bash
sudo systemctl start httpd
```

## Setup

First-time environment provisioning (EC2 instance, Prometheus, AlertManager) is documented in [`setup/README.md`](setup/README.md).

## AAP Configuration-as-Code

Push all AAP objects (credential types, credentials, projects, job templates, EDA rulebook activations) in one shot:

```bash
source .env
ansible-playbook ansible_deployment/caac/apply.yml
```

## Environment Variables

Copy `.env` and fill in your values:

| Variable | Purpose |
|----------|---------|
| `SN_INSTANCE` | ServiceNow instance URL |
| `SN_USERNAME` | ServiceNow API username |
| `SN_PASSWORD` | ServiceNow API password |
| `AAP_HOSTNAME` | AAP gateway URL |
| `AAP_TOKEN` | AAP OAuth token |
