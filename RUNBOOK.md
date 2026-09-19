# RUNBOOK â€” Mise en service de TodoInfra (prod + dev + CI/CD)

Guide pas-Ã -pas pour passer du repo vide Ã  l'application **live** sur
`https://todo.mbourouban.duckdns.org`, avec la stack complÃ¨te (Traefik â†’
Todo-app / SonarQube / Prometheus / Grafana) et le dÃ©ploiement automatique
sur push/master.

---

## 0. PrÃ©requis

| Outil    | Version mini | VÃ©rification (PowerShell) |
|----------|--------------|---------------------------|
| Terraform | 1.5+        | `terraform version`        |
| AWS CLI   | 2.x         | `aws --version`            |
| Docker    | 24+         | `docker version`           |
| Ansible   | 2.15+       | `ansible --version`        |
| git       | 2.30+       | `git --version`            |

Credential **Docker Hub** (fournis par toi) :
- Username : `demba087`
- Token (PAT) : `dckr_pat_***` (ne jamais committer, injectÃ© via les secrets GitHub)

> Ne jamais committer le token. Il est injectÃ© uniquement via les secrets GitHub.

---

## 1. CrÃ©er le dÃ©pÃ´t GitHub et pousser le projet

Le dossier local `TodoInfra` est dÃ©jÃ  initialisÃ© en git (pas de `.git` hÃ©ritÃ©,
aucun secret, aucun Ã©tat TF : repo vierge).

```powershell
cd C:\Users\lenov\Documents\TodoInfra

# CrÃ©er le repo distant (une seule fois) puis :
git remote add origin git@github.com:<VOTRE_USER>/todo-infra.git
git commit -m "Initial commit : Terraform EC2 + Ansible (Docker/Traefik/Sonarqube/Prometheus/Grafana) + CI/CD Docker Hub + app todo"
git branch -M main
git push -u origin main
```

> Le workflow ne se dÃ©clenche que sur `push` vers `main` et `pull_request`.
> Sur le premier push, seul le job **test** passe ; l'image et le dÃ©ploiement
> se jouent sur les pushes suivants.

---

## 2. Secrets GitHub (Ã  dÃ©finir une fois)

Onglet *Settings â†’ Secrets and variables â†’ Actions*, clÃ©s **exactes** :

| Nom du secret            | Valeur                                   |
|--------------------------|------------------------------------------|
| `DOCKERHUB_USERNAME`     | `demba087`                               |
| `DOCKERHUB_TOKEN`        | `dckr_pat_***` (secret injectÃ©, jamais commitÃ©)    |
| `DEPLOY_SSH_PRIVATE_KEY` | Contenu de `todo-app.pem` (clÃ© privÃ©e)    |

Variables (Settings â†’ Actions â†’ Variables) :

| Nom                        | Valeur                                             |
|----------------------------|----------------------------------------------------|
| `HOST` (prod)              | IP publique du serveur prod (issue de l'Ã©tape 3)   |
| `HOST` (dev)               | IP publique du serveur dev                          |

---

## 3. Provisionner l'infrastructure (Terraform)

**3.1 â€” Configurer l'AWS CLI**
```powershell
aws configure   # clÃ© d'accÃ¨s AWS (Access Key ID + Secret) + region eu-west-3
```

**3.2 â€” CrÃ©er la paire de clÃ©s SSH** (exactement ce que lit Terraform `key_name`)
```powershell
cd terraform
aws ec2 create-key-pair --key-name todo-app --query 'KeyMaterial' --output text | Out-File -Encoding ascii todo-app.pem
```

**3.3 â€” Appliquer (prod)**
```powershell
terraform init
terraform workspace new prod  # si absent
terraform workspace select prod
terraform apply -var-file=terraform/prod.tfvars -auto-approve
```

**3.4 â€” RÃ©cupÃ©rer l'IP et mettre Ã  jour l'inventaire Ansible**
```powershell
terraform output public_ip            # â†’ hÃ´te prod
..\scripts\update_inventory.sh prod
```

> `update_inventory.sh` injecte l'IP rÃ©elle dans `ansible/inventory/hosts.yml`.

---

## 4. Provisionner le serveur (Ansible setup + dÃ©ploiement)

Requiert la clÃ© `todo-app.pem` et l'inventaire Ã  jour :

```powershell
cd ..\ansible
ansible-galaxy install -r requirements.yml
ansible-playbook -i inventory/hosts.yml playbooks/setup.yml --limit prod
```

DÃ©ploie dans l'ordre : **Docker â†’ Traefik â†’ SonarQube â†’ Prometheus â†’ Grafana**
(routeur HTTP Sonarqube et labels Traefik dÃ©jÃ  cÃ¢blÃ©s dans les templates).

Test rapide : `curl https://sonarqube.mbourouban.duckdns.org` â†’ page Sonarqube.

---

## 5. Premier dÃ©ploiement applicatif

```powershell
ansible-playbook -i inventory/hosts.yml playbooks/deploy-app.yml --limit prod `
  --extra-vars "app_image=demba087/todo-app:latest dockerhub_username=demba087 dockerhub_token=dckr_pat_***"
```

> `app_image` = `demba087/todo-app:<tag>` (poussÃ© sur **Docker Hub** par le CI)
> â†’ en arborescence : `todo.mbourouban.duckdns.org` (route via Traefik + Let's Encrypt).

---

## 6. ProtÃ©ger `main` (push direct bloquÃ©)

```powershell
cd ..\scripts
# 1) Protection par GitHub API : PR obligatoire + 1 review + status "Tests"
.\protect_main.sh <VOTRE_USER>/todo-infra
# 2) Protection cÃ´tÃ© dÃ©pÃ´t (garde-fou : classe les pushes directs)
.\protect_main.sh --local --ref main
```

VÃ©rification : `git push origin main` doit Ãªtre **refusÃ©** (PR obligatoire).

---

## 7. Tricher les URLs (une fois le domaine DNS OK)

PrÃ©voir dans DuckDNS : `todo.`, `sonarqube.`, `grafana.`, `prometheus.`,
`traefik.` â†’ toutes pointent l'IP prod. Puis :

- Todo-app :   `https://todo.mbourouban.duckdns.org`
- SonarQube :  `https://sonarqube.mbourouban.duckdns.org`
- Prometheus : `https://prometheus.mbourouban.duckdns.org`
- Grafana :    `https://grafana.mbourouban.duckdns.org`
- Traefik :    `https://traefik.mbourouban.duckdns.org`

---

## 8. VÃ©rification finale (bon de rÃ©ception)

- [ ] `terraform output public_ip` = IP reprise dans `hosts.yml`
- [ ] `ansible-playbook setup.yml` passe sans erreur (5 rÃ´les)
- [ ] Sonarqube UP : `curl -s http://<IP>:9000/api/system/status` â†’ `"up" : true`
- [ ] Todo-app visible : `https://todo.mbourouban.duckdns.org`
- [ ] Push direct sur `main` refusÃ© par GitHub
- [ ] Secrets Docker Hub + SSH prÃ©sents dans Settings â†’ Actions

> RFC : tout changement passe par une **PR reviewÃ©e** ; le merge dÃ©clenche
> build (Docker Hub `demba087/todo-app`) + dÃ©ploiement (Ansible, cible prod).
