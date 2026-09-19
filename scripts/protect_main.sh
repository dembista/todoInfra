#!/usr/bin/env bash
# Active la protection de la branche main (bloque les push directs).
# Prérequis : gh installé et connecté (gh auth login).
# Usage : ./scripts/protect_main.sh <owner/repo>
set -euo pipefail

REPO="${1:?Usage: $0 <owner/repo>}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

gh api "repos/$REPO/branches/main/protection" \
  --method PUT \
  --input "$DIR/main-protection.json"

echo "Protection de la branche main activée sur $REPO :"
echo "  - Push direct bloqué"
echo "  - PR requise avec 1 review approuvée"
echo "  - Checks requis : Tests"