# Utilisation

Le repository contient :
- `terraform/` : création de 2 instances EC2 (dev et prod) sur AWS
- `ansible/` : installation de Docker, Traefik, Prometheus et Grafana sur les serveurs
- `todo-app/` : l'application todo (Node.js/Express) à déployer
- `.github/workflows/` : pipeline CI/CD (develop -> dev, main -> prod)

## Prérequis

- Terraform >= 1.5
- Ansible >= 2.14
- Credentials AWS (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
- Une paire de clés SSH
- Un compte GitHub

## Étapes

### 1. Provisionner les serveurs (Terraform)

```bash
cd terraform

# Dev
terraform init
terraform workspace new dev || true
terraform apply -var-file=dev.tfvars

# Prod
terraform workspace new prod || true
terraform apply -var-file=prod.tfvars
```

Récupérer les IP publiques :
```bash
terraform output public_ip
```

### 2. Configurer l'inventaire Ansible

Remplacer `DEV_PUBLIC_IP` et `PROD_PUBLIC_IP` dans `ansible/inventory/hosts.yml`.

### 3. Installer les outils (Ansible)

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory/hosts.yml playbooks/setup.yml
```

- Docker (avec plugin compose)
- Traefik (port 80/443)
- Prometheus (port 9090)
- Grafana (port 3000)

### 4. Domaines (optionnel)

Si vous possédez un domaine :
1. Définir `domain_name` dans `ansible/group_vars/all.yml`
2. Créer un enregistrement DNS A pointant vers les IP des instances
3. Renseigner le domaine dans `terraform/*.tfvars` pour la création automatique de la zone Route 53

Sans domaine, les applications sont accessibles via l'IP publique :
- Application : http://<IP>/
- Traefik dashboard : http://<IP>:8080
- Prometheus : http://<IP>:9090
- Grafana : http://<IP>:3000

### 5. Déployer l'application via le CI/CD

Le workflow GitHub Actions s'occupe de tout :
- Push sur `develop` -> build + deploy sur le serveur dev
- Push sur `main` -> build + deploy sur le serveur prod