#!/usr/bin/env bash
set -euo pipefail

# Run the setup playbook (monitoring stack, CMDB registration, webhook bridge).
# Sources the repo-root .env so ServiceNow credentials are available automatically.
#
# Usage:
#   ./setup/scripts/setup-apply.sh
#
# Required env (from top-level .env):
#   SN_INSTANCE, SN_USERNAME, SN_PASSWORD

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PLAYBOOK="${REPO_ROOT}/setup/playbooks/setup_monitoring_stack.yml"
INVENTORY="${REPO_ROOT}/setup/playbooks/inventory/hosts.yml"

# Load top-level .env if present
if [[ -f "${REPO_ROOT}/.env" ]]; then
  echo "Loading environment from ${REPO_ROOT}/.env"
  # shellcheck disable=SC2046
  export $(grep -v '^#' "${REPO_ROOT}/.env" | xargs -I{} echo {})
fi

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "Error: ansible-playbook not found. Install Ansible first."
  exit 1
fi

if [[ ! -f "${INVENTORY}" ]]; then
  echo "Error: Inventory not found at ${INVENTORY}"
  echo "Run 'terraform apply' in setup/terraform/ first."
  exit 1
fi

ansible-playbook "${PLAYBOOK}" -i "${INVENTORY}" "$@"
