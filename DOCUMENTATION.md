# TodoInfra — Documentation technique complète

Documentation de référence du projet **TodoInfra** : infrastructure-as-code sur AWS, provisionnement, surveillance, et déploiement continu d'une application To-Do.

- Dépôt : `https://github.com/dembista/todoInfra`
- Domaine public : `mbourouban.duckdns.org` (DuckDNS)
- Application : `https://todo.mbourouban.duckdns.org`

---

## 1. Vue d'ensemble

| Couche      | Technologie        | Rôle                                                     |
|-------------|--------------------|----------------------------------------------------------|
| Infra       | Terraform          | 2 instances EC2 (dev + prod), SG existants importés, EIP |
| Configuration | Ansible          | Docker, Traefik (proxy/TLS), SonarQube, Prometheus, Grafana |
| Monitoring  | Prometheus + Grafana | Collecte CPU/RAM/disque/conteneurs, alertes, dashboards  |
| Application | Node.js / Express  | API To-Do conteneurisée (Docker Hub `demba087/todo-app`)  |
| CI/CD       | GitHub Actions     | Tests → build/push image → déploiement Ansible (prod)     |
| DNS         | DuckDNS            | `mbourouban.duckdns.org` → IP publique prod, auto-update  |

### Flux global

```
develop / main ──push──▶ GitHub Actions
                              │
                              ▼
                    1. Tests (npm test)
                    2. Build Docker + push → Docker Hub (demba087/todo-app)
                    3. Déploiement Ansible → serveur AWS (Traefik, app)
                              │
                              ▼
                    mbourouban.duckdns.org → EC2 prod
```

---

## 2. Architecture AWS

| Ressource | Prod | Dev | Détails |
|-----------|------|-----|---------|
| Instance EC2 | `i-06dfb5c76f44dce8e` | `i-099ef7f5ff2cebd17` | `t3.small` (2 vCPU / 2 Go RAM), plan Free Tier |
| IP élastique (EIP) | `13.39.134.65` | `15.188.210.106` | associées aux instances |
| Elastique ID | `eipalloc-025b7ffa925ba23e0` | `eipalloc-089db3c6029d891a5` | |
| Security Group | `sg-0e6ae8bc4595fab18` (`todo-app-prod-sg`) | `sg-01056d0c667b20044` (`todo-app-dev-sg`) | 22, 80, 443, 8080, 3000, 9090 |
| Volume root | 30 Go (EBS gp2, agrandi de 20→30 Go) | 30 Go | |
| Région / AZ | `eu-west-3` (Paris) | `eu-west-3` | |

**Note importante** : les SG et EIP sont **préexistants** et ont été **importés** dans les états Terraform (aucune destruction). Terraform ne crée que les instances EC2.

### Modèle Terraform (`terraform/main.tf`)

- `aws_security_group.public_sg` — SG existant importé
- `aws_instance.web` — instance EC2 (`var.instance_type`, `var.key_name`, `root_block_device` 30 Go via `var.root_volume_size`)
- `aws_eip.web` — EIP existante importée + association à l'EC2

Workspaces : `default`, `dev`, `prod` (états locaux `terraform.tfstate.d/`).

---

## 3. Actifs déployés sur les serveurs

| Conteneur      | Image                              | Ports exposés          | Rôle                              |
|----------------|------------------------------------|------------------------|------------------------------------|
| `todo-app`     | `demba087/todo-app`                | interne 3000 (via Traefik) | Application To-Do              |
| `traefik`      | `traefik` (dernière)               | 80, 443, 8080          | Reverse proxy, TLS Let's Encrypt, dashboard |
| `sonarqube`    | `sonarqube:lts-community`          | 127.0.0.1:9000         | Analyse statique de code           |
| `sonarqube_db` | `postgres:16`                      | interne 5432           | Base PostGreSQL de SonarQube       |
| `prometheus`   | `prom/prometheus:v2.51.0`          | 127.0.0.1:9090         | Collecte de métriques (à terminer) |
| `node-exporter`| `prom/node-exporter:v1.8.2`        | 9100 (réseau docker)   | Métriques système hôte             |
| `grafana`      | `grafana/grafana:11.0.0`           | 3000 (+ proxys Traefik)| Dashboards, datasource Prometheus  |

### Topologie réseau Docker

- Réseau externe partagé `traefik` : tous les services joignables entre eux par nom.
- Traefik découvre les services par **labels Docker** (`exposedByDefault: false` → seul ce qui a `traefik.enable=true` est routé).

---

## 4. Rôles Ansible

Les rôles vivent dans `ansible/roles/` (chemin requis `ANSIBLE_ROLES_PATH`).

### 4.1 `docker`
- Installation du moteur Docker + plugin Compose sur Ubuntu.

### 4.2 `traefik`
- `traefik.yml` (statique) : dashboard (`/api`, `/dashboard` sur 8080), entrées **web** (80), **websecure** (443), **traefik** (8080), metrics Prometheus, provider Docker + fichier, resolveur ACME Let's Encrypt (HTTP challenge sur 80).
- `dynamic.yml` : routeur du dashboard.
- Redirection 80 → 443 automatique quand un domaine est défini.

### 4.3 `sonarqube`
- Règle kernel `vm.max_map_count=262144` (réquis Elasticsearch) via `ansible.posix.sysctl`.
- Répertoires `/opt/sonarqube/{data,extensions,logs,db_data}` avec bons UID (1000 Sonar, 999 Postgres).
- Dans un `docker-compose.yml` : `sonarqube` + `sonarqube_db` (Postgres 16).
- Port 9000 exposé sur `127.0.0.1` (bind local, pas public) + labels Traefik (`sonarqube.<domaine>`) avec TLS Let's Encrypt quand `domain_name` est défini.
- Tâche d'attente de l'API (`/api/system/status` → HTTP 200).

### 4.4 `prometheus`
- Config `prometheus.yml` : profils `prometheus` (self), `traefik` (`traefik:8080`), `node` (`node-exporter:9100`).
- Fichier de règles d'alerte `alert-rules.yml` (cf. section 6).
- Compose avec Prometheus + **node-exporter**.

### 4.5 `grafana`
- Mailer `prometheus-datasource.yml` → source Prometheus par défaut.
- Provider de dashboards + dashboard JSON `todo-infra-dashboard.json` provisionnés.
- Montage des dashboards en lecture seule ; credentials `grafana_admin_user/password` (défauts à changer).

---

## 5. CI/CD (GitHub Actions)

### 5.1 `deploy.yml` (principal)
Déclencheurs : `push`/`pull_request` sur `main` et `develop`.

| Job | Actions |
|-----|---------|
| **test** | Checkout, Node 20, `npm ci`, `npm test` (dossier `todo-app/`) |
| **build-and-push-image** | Connexion Docker Hub (`DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN`), build+push `demba087/todo-app:<branche>` + `:latest` |
| **deploy** | Installer Ansible + collection `community.docker`, écrire la clé SSH `DEPLOY_SSH_PRIVATE_KEY`, choisir la cible (main → **prod**, autre → **dev**), `ansible-playbook deploy-app.yml` |

Le job `deploy` déploie l'app conteneurisée avec ses labels Traefik (Host = `todo.mbourouban.duckdns.org` pour prod, TLS Let's Encrypt).

### 5.2 `monitoring.yml`
Provisions **setup.yml** complet (Docker → Traefik → SonarQube → Prometheus → Grafana) sur prod + dev.
Déclencheurs : `workflow_dispatch` + push sur les chemins `ansible/roles/**`, `ansible/playbooks/setup.yml`, `ansible/inventory/**`.
Installe les collections nécessaires (`community.docker`, `ansible.posix`) et définit `ANSIBLE_ROLES_PATH`.

### 5.3 `duckdns.yml`
Cron toutes les 5 minutes : met à jour `mbourouban.duckdns.org` vers l'IP de `vars.PROD_HOST` via l'API DuckDNS (token en secret `DUCKDNS_TOKEN`).

### 5.4 Secrets et variables GitHub requis

**Secrets** (`Settings → Secrets and variables → Actions`) :

| Nom | Usage |
|-----|-------|
| `DOCKERHUB_USERNAME` | Login Docker Hub (build/push image) |
| `DOCKERHUB_TOKEN` | Token Docker Hub (PAT) |
| `DEPLOY_SSH_PRIVATE_KEY` | Clé privée SSH `todo-app.pem` (déploiement Ansible) |
| `DUCKDNS_TOKEN` | Token DuckDNS (auto-update domaine) |

**Variables** :

| Nom | Valeur |
|-----|--------|
| `PROD_HOST` | `13.39.134.65` |
| `DEV_HOST` | `15.188.210.106` |

---

## 6. Supervision et alerting

### Alertes Prometheus (`ansible/roles/prometheus/templates/alert-rules.yml.j2`)

| Alerte | Expression (résumé) | Criticité | Sujet |
|--------|--------------------|-----------|-------|
| `ServeurInjoignable` | `up == 0` (2 min) | critical | Serveur de scraping injoignable |
| `CPUEleve` | CPU > 85 % (10 min) | warning | Saturation CPU |
| `MemoirePlusEchange` | RAM utilisée > 90 % (5 min) | warning | Pression mémoire |
| `DisquePresquePlein` | disque > 85 % (10 min) | warning | Disque plein |
| `ChargeServeurElevee` | `load1 > 4` (10 min) | critical | Surcharge système (SSH instable) |
| `ConteneurNonDemarre` | conteneur en crash-loop (1 min) | critical | Redémarrages en boucle |
| `RedondancePerdue` | réplicas d'un job non répondants (5 min) | critical | Perte de redondance / HA |
| `PortServiceInaccessible` | target `up == 0` pour un job (5 min) | critical | Failles réseau / port |

### Dashboard Grafana `todo-infra-dashboard.json`

Panels : CPU %, RAM utilisée %, disque %, load average, courbes CPU/RAM par instance, table des conteneurs (démarrage), table des **alertes actives**.

### Vérifications utiles

```bash
# Statut SonarQube (depuis l'hôte)
curl -s http://127.0.0.1:9000/api/system/status

# Règle kernel Elasticsearch
sysctl vm.max_map_count        # attendu 262144

# Prometheus targets
curl -s http://127.0.0.1:9090/api/v1/targets | jq

# Conteneurs
docker ps
```

---

## 7. DNS (DuckDNS)

| Enregistrement | Cible |
|----------------|-------|
| `mbourouban.duckdns.org` | 13.39.134.65 (prod) |
| `todo.mbourouban.duckdns.org` | 13.39.134.65 |
| `sonarqube.mbourouban.duckdns.org` | 13.39.134.65 |
| `grafana.mbourouban.duckdns.org` | (à créer si besoin) |
| `prometheus.mbourouban.duckdns.org` | (à créer si besoin) |

**Token DuckDNS** : `18b1c348-...` (secret GitHub `DUCKDNS_TOKEN`, jamais commité en clair).

Le workflow `duckdns.yml` maintient le domaine à jour automatiquement (toutes les 5 min) et peut être déclenché manuellement (`workflow_dispatch`).

---

## 8. Sécurité

- **Pas de secret commité** : `.gitignore` exclut `*.pem`, `*.tfstate*`, `.env`, collections Ansible.
- Tokens injectés uniquement via **secrets GitHub**.
- Port 9000 SonarQube en **bind local** (`127.0.0.1`), pas exposé publiquement.
- SSH : clé `todo-app.pem` (chmod 600), hosts vérifiés via `StrictHostKeyChecking=off` en CI.
- Grafana : `GF_USERS_ALLOW_SIGN_UP=false`, admin configuré (défaut `grafana_admin_password` → **à changer en secret**).
- Sur les deux SG, `ssh_cidr=0.0.0.0/0` — à restreindre en durcissement (voir section 9).

---

## 9. Limites connues et actions à mener

| # | Problème | Impact | Action |
|---|----------|--------|--------|
| 1 | **RAM 2 Go (t3.small) saturée** — SonarQube (~1,25 Go) + app + Traefik → OOM / `sshd: Connection closed` | Déploiements intermittents, SSH instable | **Upgrader le compte AWS** (Free Tier bloque `ModifyInstanceType`), puis passer à `t3.medium` via `terraform apply` |
| 2 | Prometheus/Grafana non encore démarrés sur les hôtes | Monitoring incomplet | Relancer `monitoring.yml` après l'upgrade |
| 3 | TLS Let's Encrypt **certificat par défaut** actif (ACME pas encore émis) | `https://todo.mbourouban...` rejeté par navigateur | Pourvoir le routeur (domaine) puis émettre le certificat via Traefik |
| 4 | Bastion SSH ouvert `0.0.0.0/0` | Exposition | Restreindre `ssh_cidr` dans les `.tfvars` |
| 5 | Nouvelles sous-domaines DuckDNS (`grafana.`, `prometheus.`) à créer côté DuckDNS si routés par domaine | URL manquantes | Créer les sous-domaines sur DuckDNS |
| 6 | Credentials Grafana/Sonar par défaut (`change-me-*`) | Faiblesse | Mettre en secret réel |

---

## 10. Procédures courantes

### Déployer l'application (manuel)
```powershell
# Depuis la machine de dev (Ansible dans WSL)
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/deploy-app.yml --limit prod `
  --extra-vars "app_image=demba087/todo-app:latest"
```

### Relancer le provisionnement complet
Via GitHub (`Actions → Monitoring & Infrastructure → Run workflow`) — recommandé pour stabilité SSH.

### Mettre à jour l'IP de l'inventaire Ansible
```bash
./scripts/update_inventory.sh prod   # injecte l'IP terraform output dans hosts.yml
```

### Redémarrer SonarQube
```bash
docker compose -f /opt/sonarqube/docker-compose.yml up -d --force-recreate
```

---

## 11. Checklist de bon de réception

- [ ] `terraform output public_ip` = IP de `ansible/inventory/hosts.yml`
- [ ] `setup.yml` passe sans erreur (5 rôles) — ok=..., failed=0
- [ ] SonarQube UP : `curl http://127.0.0.1:9000/api/system/status` → `"status":"UP"`
- [ ] Todo-app : `https://todo.mbourouban.duckdns.org` → 200 + certificat valide
- [ ] Prometheus : targets node + traefik en état `up`
- [ ] Grafana : dashboard « Todo-Infra » visible avec données
- [ ] Alertes : AUCUNE alerte « firing » après 10 min
- [ ] Push sur `main` direct refusé / PR obligatoire