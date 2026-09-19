#!/usr/bin/env bash
# Récupère les IP publiques depuis Terraform et met à jour l'inventaire Ansible.
# Usage : ./update_inventory.sh <dev|prod|all>
set -euo pipefail

update_env() {
  local env="$1"
  local ip
  ip=$(cd terraform && terraform workspace select "$env" && terraform output public_ip | tr -d '"')
  if [[ -z "$ip" ]]; then
    echo "Impossible de récupérer l'IP pour $env" >&2
    exit 1
  fi
  echo "Adresse IP $env : $ip"
  local upper
  upper=$(echo "$env" | tr '[:lower:]' '[:upper:]')
  sed -i "s/${upper}_PUBLIC_IP/${ip}/g" ansible/inventory/hosts.yml
}

case "${1:-all}" in
  dev)  update_env dev ;;
  prod) update_env prod ;;
  all)  update_env dev; update_env prod ;;
  *)    echo "Usage: $0 <dev|prod|all>"; exit 1 ;;
esac

echo "Inventaire Ansible mis à jour."