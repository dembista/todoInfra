# Infra-as-code : EC2 dev & prod (Terraform) + provisionnement (Ansible) + CI/CD todo-app

Ce repository déploie une application **todo** (Node.js/Express) via un workflow complet :

| Couche       | Techno              | Rôle                                             |
|--------------|---------------------|--------------------------------------------------|
| Infra        | Terraform           | 2 instances EC2 (one for `dev`, one for `prod`) |
| Config       | Ansible             | Docker, Traefik, Prometheus, Grafana            |
| App          | Node.js / Express   | Application todo (conteneurisée)                 |
| CI/CD        | GitHub Actions      | develop → dev, main → prod                       |

## Structure

```
.
├── terraform/                 # Infra AWS (EC2 dev/prod)
│   ├── main.tf                # VPC, SG, instance, EIP, Route53
│   ├── variables.tf
│   ├── outputs.tf
│   ├── dev.tfvars             # Variables pour l'env dev
│   └── prod.tfvars            # Variables pour l'env prod
├── ansible/
│   ├── inventory/hosts.yml    # Inventaire (IP des serveurs)
│   ├── group_vars/            # Variables partagées
│   ├── roles/
│   │   ├── docker/            # Installation de Docker
│   │   ├── traefik/           # Reverse proxy + Let's Encrypt
│   │   ├── prometheus/        # Collecte de métriques
│   │   └── grafana/           # Tableaux de bord
│   ├── playbooks/setup.yml    # Provisionnement des serveurs
│   └── playbooks/deploy-app.yml # Déploiement de l'app (utilisé par le CI)
├── todo-app/                  # Application todo
│   ├── src/server.js
│   ├── public/index.html
│   ├── test/                  # Tests
│   ├── Dockerfile
│   └── package.json
├── .github/workflows/deploy.yml # Pipeline CI/CD
└── scripts/
    ├── update_inventory.sh    # Met à jour les IPs dans l'inventaire
    └── protect_main.sh        # Active la protection de main
```

## Démarrage rapide

### 1. Terraform — créer les serveurs

```bash
cd terraform

# dev
terraform init
terraform workspace new dev || true
terraform apply -var-file=dev.tfvars -auto-approve

# prod
terraform workspace new prod || true
terraform apply -var-file=prod.tfvars -auto-approve

terraform output public_ip
```

Credentials AWS : `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` en variables d'environnement.

> Remplissez `dev.tfvars` / `prod.tfvars` (VPC, subnet, AMI, clé publique SSH).

### 2. Ansible — installer les outils

Remplacer `DEV_PUBLIC_IP` / `PROD_PUBLIC_IP` dans `ansible/inventory/hosts.yml`
(ou exécuter `./scripts/update_inventory.sh`).

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory/hosts.yml playbooks/setup.yml
```

Installe sur chaque serveur :
- **Docker** + plugin compose
- **Traefik** (reverse proxy, ports 80/443)
- **Prometheus** (métriques, port 9090)
- **Grafana** (dashboard, port 3000)

Accès sans domaine : `http://<IP>` (app), `http://<IP>:8080` (Traefik),
`http://<IP>:9090` (Prometheus), `http://<IP>:3000` (Grafana).

### 3. CI/CD

Le workflow `.github/workflows/deploy.yml` :
- Push sur **develop** → build image (`:develop`) + déploiement sur le serveur **dev**
- Push sur **main** → build image (`:main`) + déploiement sur le serveur **prod**
- Les tests s'exécutent à chaque push / PR

#### Secrets et variables GitHub requis

| Type            | Nom                     | Valeur                            |
|-----------------|-------------------------|-----------------------------------|
| Secret          | `DEPLOY_SSH_PRIVATE_KEY`| Clé privée SSH vers les serveurs |
| Variable repo   | `DEV_HOST`              | IP publique du serveur dev       |
| Variable repo   | `PROD_HOST`             | IP publique du serveur prod      |

### 4. Protéger la branche main (bloquer les push directs)

```bash
gh auth login
./scripts/protect_main.sh <owner/repo>
```

Effets :
- Aucun push direct sur `main`
- PR obligatoires avec au moins 1 review
- Checks requis (`Tests`, `Build & push de l'image Docker`)
- Force-push et suppression désactivés

## Domaine / sous-domaine (optionnel)

Si vous disposez d'un domaine :
1. Dans `ansible/group_vars/all.yml` : `domain_name: todo.example.com`
2. Dans `terraform/prod.tfvars` : `domain_name` + `route53_zone_id` (création auto du DNS)
3. Les sous-domaines `todo.`, `traefik.`, `prometheus.`, `grafana.` sont routés en HTTPS (Let's Encrypt)

## Roadmap possible

- Backend distants (S3 + DynamoDB lock) pour Terraform en équipe
- Dashboards Grafana provisionnés (JSON)
- Alertes Prometheus (Alertmanager + Slack)