# RUNBOOK — Mise en service de TodoInfra (prod + dev + CI/CD)

Guide pas-à-pas pour passer du repo vide à l'application **live** sur
`https://todo.madakhoun.duckdns.org`, avec la stack complète (Traefik →
Todo-app / SonarQube / Prometheus / Grafana) et le déploiement automatique
sur push/master.

---

## 0. Prérequis

| Outil    | Version mini | Vérification (PowerShell) |
|----------|--------------|---------------------------|
| Terraform | 1.5+        | `terraform version`        |
| AWS CLI   | 2.x         | `aws --version`            |
| Docker    | 24+         | `docker version`           |
| Ansible   | 2.15+       | `ansible --version`        |
| git       | 2.30+       | `git --version`            |

Credential **Docker Hub** (fournis par toi) :
- Username : `demba087`
- Token (PAT) : `dckr_pat_***` (ne jamais committer, injecté via les secrets GitHub)

> Ne jamais committer le token. Il est injecté uniquement via les secrets GitHub.

---

## 1. Créer le dépôt GitHub et pousser le projet

Le dossier local `TodoInfra` est déjà initialisé en git (pas de `.git` hérité,
aucun secret, aucun état TF : repo vierge).

```powershell
cd C:\Users\lenov\Documents\TodoInfra

# Créer le repo distant (une seule fois) puis :
git remote add origin git@github.com:<VOTRE_USER>/todo-infra.git
git commit -m "Initial commit : Terraform EC2 + Ansible (Docker/Traefik/Sonarqube/Prometheus/Grafana) + CI/CD Docker Hub + app todo"
git branch -M main
git push -u origin main
```

> Le workflow ne se déclenche que sur `push` vers `main` et `pull_request`.
> Sur le premier push, seul le job **test** passe ; l'image et le déploiement
> se jouent sur les pushes suivants.

---

## 2. Secrets GitHub (à définir une fois)

Onglet *Settings → Secrets and variables → Actions*, clés **exactes** :

| Nom du secret            | Valeur                                   |
|--------------------------|------------------------------------------|
| `DOCKERHUB_USERNAME`     | `demba087`                               |
| `DOCKERHUB_TOKEN`        | `dckr_pat_***` (secret injecté, jamais commité)    |
| `DEPLOY_SSH_PRIVATE_KEY` | Contenu de `todo-app.pem` (clé privée)    |

Variables (Settings → Actions → Variables) :

| Nom                        | Valeur                                             |
|----------------------------|----------------------------------------------------|
| `HOST` (prod)              | IP publique du serveur prod (issue de l'étape 3)   |
| `HOST` (dev)               | IP publique du serveur dev                          |

---

## 3. Provisionner l'infrastructure (Terraform)

**3.1 — Configurer l'AWS CLI**
```powershell
aws configure   # clé d'accès AWS (Access Key ID + Secret) + region eu-west-3
```

**3.2 — Créer la paire de clés SSH** (exactement ce que lit Terraform `key_name`)
```powershell
cd terraform
aws ec2 create-key-pair --key-name todo-app --query 'KeyMaterial' --output text | Out-File -Encoding ascii todo-app.pem
```

**3.3 — Appliquer (prod)**
```powershell
terraform init
terraform workspace new prod  # si absent
terraform workspace select prod
terraform apply -var-file=terraform/prod.tfvars -auto-approve
```

**3.4 — Récupérer l'IP et mettre à jour l'inventaire Ansible**
```powershell
terraform output public_ip            # → hôte prod
..\scripts\update_inventory.sh prod
```

> `update_inventory.sh` injecte l'IP réelle dans `ansible/inventory/hosts.yml`.

---

## 4. Provisionner le serveur (Ansible setup + déploiement)

Requiert la clé `todo-app.pem` et l'inventaire à jour :

```powershell
cd ..\ansible
ansible-galaxy install -r requirements.yml
ansible-playbook -i inventory/hosts.yml playbooks/setup.yml --limit prod
```

Déploie dans l'ordre : **Docker → Traefik → SonarQube → Prometheus → Grafana**
(routeur HTTP Sonarqube et labels Traefik déjà câblés dans les templates).

Test rapide : `curl https://sonarqube.madakhoun.duckdns.org` → page Sonarqube.

---

## 5. Premier déploiement applicatif

```powershell
ansible-playbook -i inventory/hosts.yml playbooks/deploy-app.yml --limit prod `
  --extra-vars "app_image=demba087/todo-app:latest dockerhub_username=demba087 dockerhub_token=dckr_pat_***"
```

> `app_image` = `demba087/todo-app:<tag>` (poussé sur **Docker Hub** par le CI)
> → en arborescence : `todo.madakhoun.duckdns.org` (route via Traefik + Let's Encrypt).

---

## 6. Protéger `main` (push direct bloqué)

```powershell
cd ..\scripts
# 1) Protection par GitHub API : PR obligatoire + 1 review + status "Tests"
.\protect_main.sh <VOTRE_USER>/todo-infra
# 2) Protection côté dépôt (garde-fou : classe les pushes directs)
.\protect_main.sh --local --ref main
```

Vérification : `git push origin main` doit être **refusé** (PR obligatoire).

---

## 7. Tricher les URLs (une fois le domaine DNS OK)

Prévoir dans DuckDNS : `todo.`, `sonarqube.`, `grafana.`, `prometheus.`,
`traefik.` → toutes pointent l'IP prod. Puis :

- Todo-app :   `https://todo.madakhoun.duckdns.org`
- SonarQube :  `https://sonarqube.madakhoun.duckdns.org`
- Prometheus : `https://prometheus.madakhoun.duckdns.org`
- Grafana :    `https://grafana.madakhoun.duckdns.org`
- Traefik :    `https://traefik.madakhoun.duckdns.org`

---

## 8. Vérification finale (bon de réception)

- [ ] `terraform output public_ip` = IP reprise dans `hosts.yml`
- [ ] `ansible-playbook setup.yml` passe sans erreur (5 rôles)
- [ ] Sonarqube UP : `curl -s http://<IP>:9000/api/system/status` → `"up" : true`
- [ ] Todo-app visible : `https://todo.madakhoun.duckdns.org`
- [ ] Push direct sur `main` refusé par GitHub
- [ ] Secrets Docker Hub + SSH présents dans Settings → Actions

> RFC : tout changement passe par une **PR reviewée** ; le merge déclenche
> build (Docker Hub `demba087/todo-app`) + déploiement (Ansible, cible prod).
