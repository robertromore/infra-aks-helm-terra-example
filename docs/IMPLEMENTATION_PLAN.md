# Laravel API Implementation Plan

This comprehensive guide will walk you through implementing a production-ready Laravel API infrastructure using Larakube on Azure Kubernetes Service (AKS).

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Phase 1: Infrastructure Setup](#phase-1-infrastructure-setup)
3. [Phase 2: Application Preparation](#phase-2-application-preparation)
4. [Phase 3: CI/CD Pipeline](#phase-3-cicd-pipeline)
5. [Phase 4: Deployment](#phase-4-deployment)
6. [Phase 5: Production Readiness](#phase-5-production-readiness)
7. [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Tools
Install the following tools on your local machine:

```bash
# Azure CLI
curl -sL https://aka.ms/InstallAzureCLI | sudo bash

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Helm
curl https://get.helm.sh/helm-v3.12.0-linux-amd64.tar.gz | tar xz
sudo mv linux-amd64/helm /usr/local/bin/

# Terraform
wget https://releases.hashicorp.com/terraform/1.5.0/terraform_1.5.0_linux_amd64.zip
unzip terraform_1.5.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Docker
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
```

### Azure Account Setup
1. Create an Azure account if you don't have one
2. Create a subscription
3. Install and login to Azure CLI:
```bash
az login
az account set --subscription "your-subscription-id"
```

### GitHub Setup
1. Fork or clone this repository
2. Enable GitHub Container Registry (GHCR) for your repository
3. Create a Personal Access Token with `packages:write` permissions

## Phase 1: Infrastructure Setup

### Step 1.1: Create Azure Resource Group
```bash
# Set your variables
RESOURCE_GROUP="laravel-api-rg"
LOCATION="eastus"
AKS_NAME="laravel-api-aks"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION
```

### Step 1.2: Deploy AKS Cluster with Terraform
```bash
cd infrastructure/terraform

# Copy and customize the terraform variables
cp terraform.tfvars.example terraform.tfvars
cp environments/production.tfvars.example environments/production.tfvars

# Edit terraform.tfvars with your values
vim terraform.tfvars
```

**Required terraform.tfvars configuration:**
```hcl
# Basic Configuration
resource_group_name = "laravel-api-rg"
location           = "eastus"
cluster_name       = "laravel-api-aks"

# Cloudflare (if using)
cloudflare_api_token = "your-cloudflare-api-token"
cloudflare_zone_id   = "your-zone-id"

# Domain Configuration  
domain_name = "yourdomain.com"
```

Deploy the infrastructure:
```bash
# Initialize Terraform
terraform init

# Plan the deployment
terraform plan -var-file="environments/production.tfvars"

# Apply the configuration
terraform apply -var-file="environments/production.tfvars"
```

### Step 1.3: Connect to AKS Cluster
```bash
# Get AKS credentials
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_NAME

# Verify connection
kubectl get nodes
```

### Step 1.4: Install Core Dependencies
```bash
# Add Helm repositories
helm repo add larakube https://charts.larakube.com
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add jetstack https://charts.jetstack.sh
helm repo add traefik https://traefik.github.io/charts
helm repo update

# Install Cert-Manager
kubectl create namespace cert-manager
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --set installCRDs=true

# Install Traefik (if not using Azure Application Gateway)
kubectl create namespace traefik
helm install traefik traefik/traefik \
  --namespace traefik \
  --set deployment.kind=DaemonSet \
  --set ports.web.redirectTo=websecure \
  --set ports.websecure.tls.enabled=true
```

## Phase 2: Application Preparation

### Step 2.1: Prepare Laravel Application
1. **Ensure your Laravel app is in `apps/api/` directory**
2. **Create required configuration files:**

Create `apps/api/.env.testing`:
```env
APP_NAME="Laravel API"
APP_ENV=testing
APP_KEY=base64:your-testing-key
APP_DEBUG=true
APP_URL=http://localhost

DB_CONNECTION=pgsql
DB_HOST=localhost
DB_PORT=5432
DB_DATABASE=testing
DB_USERNAME=laravel
DB_PASSWORD=password

CACHE_DRIVER=array
QUEUE_CONNECTION=sync
SESSION_DRIVER=array

REDIS_HOST=localhost
REDIS_PORT=6379
```

Create `apps/api/Dockerfile`:
```dockerfile
FROM php:8.2-fpm-alpine

# Install system dependencies
RUN apk add --no-cache \
    git \
    curl \
    libpng-dev \
    libxml2-dev \
    zip \
    unzip \
    postgresql-dev

# Install PHP extensions
RUN docker-php-ext-install \
    pdo_pgsql \
    mbstring \
    exif \
    pcntl \
    bcmath \
    gd

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Set working directory
WORKDIR /var/www/html

# Copy application files
COPY . .

# Install dependencies
RUN composer install --no-dev --optimize-autoloader

# Set permissions
RUN chown -R www-data:www-data /var/www/html

EXPOSE 8000

CMD php artisan serve --host=0.0.0.0 --port=8000
```

### Step 2.2: Update Repository Configuration
Replace placeholders in configuration files:

```bash
# Update image repository in values files
find infrastructure/helm -name "values*.yaml" -exec sed -i 's/GITHUB_USERNAME/your-github-username/g' {} \;
find infrastructure/helm -name "values*.yaml" -exec sed -i 's/REPO_NAME/your-repo-name/g' {} \;

# Update domains
find infrastructure/helm -name "values*.yaml" -exec sed -i 's/api.example.com/api.yourdomain.com/g' {} \;
find infrastructure/helm -name "values*.yaml" -exec sed -i 's/api.yourcompany.com/api.yourdomain.com/g' {} \;
```

## Phase 3: CI/CD Pipeline

### Step 3.1: Configure GitHub Secrets
In your GitHub repository, add these secrets (Settings → Secrets and Variables → Actions):

**Required Secrets:**
```bash
# Azure Credentials for Service Principal
AZURE_CREDENTIALS='
{
  "clientId": "your-client-id",
  "clientSecret": "your-client-secret", 
  "subscriptionId": "your-subscription-id",
  "tenantId": "your-tenant-id"
}'

# Slack Notifications (optional)
SLACK_WEBHOOK=https://hooks.slack.com/services/your/webhook/url
```

### Step 3.2: Create Azure Service Principal
```bash
# Create service principal for GitHub Actions
az ad sp create-for-rbac \
  --name "github-actions-laravel-api" \
  --role contributor \
  --scopes /subscriptions/your-subscription-id/resourceGroups/$RESOURCE_GROUP \
  --sdk-auth

# Copy the JSON output to AZURE_CREDENTIALS secret
```

### Step 3.3: Test CI/CD Pipeline
```bash
# Create a test branch and push changes
git checkout -b feature/test-deployment
git add .
git commit -m "Test deployment pipeline"
git push origin feature/test-deployment

# Create a pull request to trigger the pipeline
```

## Phase 4: Deployment

### Step 4.1: Deploy to Staging
```bash
# Push to develop branch to trigger staging deployment
git checkout develop
git merge feature/test-deployment
git push origin develop
```

Monitor the deployment:
```bash
# Watch GitHub Actions workflow
# Check staging deployment
kubectl get pods -n staging
kubectl get ingress -n staging
```

### Step 4.2: Deploy to Production
```bash
# Create production secrets
kubectl create namespace production

# Create image pull secret for GHCR
kubectl create secret docker-registry ghcr-pull-secret \
  --namespace=production \
  --docker-server=ghcr.io \
  --docker-username=your-github-username \
  --docker-password=your-github-token

# Create application secrets
kubectl create secret generic api-secrets-prod \
  --namespace=production \
  --from-literal=db-host="your-postgres-host" \
  --from-literal=db-database="laravel_prod" \
  --from-literal=db-username="laravel_prod" \
  --from-literal=db-password="your-secure-password" \
  --from-literal=app-key="base64:your-production-app-key" \
  --from-literal=jwt-secret="your-jwt-secret"

# Deploy to production by merging to main
git checkout main
git merge develop
git push origin main
```

### Step 4.3: Manual Deployment (Alternative)
If you prefer manual deployment:

```bash
cd infrastructure/helm/api

# Update dependencies
helm dependency update

# Deploy to staging
helm upgrade --install api-staging . \
  --namespace staging \
  --create-namespace \
  --values values.yaml \
  --set image.tag=latest

# Deploy to production
helm upgrade --install api-production . \
  --namespace production \
  --create-namespace \
  --values values.yaml \
  --values values-production.yaml \
  --set image.tag=latest
```

## Phase 5: Production Readiness

### Step 5.1: Configure Monitoring
```bash
# Install monitoring stack (if not deployed via Terraform)
kubectl create namespace monitoring

# Deploy Prometheus and Grafana
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring
```

### Step 5.2: Configure DNS
Update your DNS records to point to the Traefik LoadBalancer:

```bash
# Get LoadBalancer IP
kubectl get service -n traefik traefik

# Update DNS records
# api.yourdomain.com → LoadBalancer_IP
```

### Step 5.3: Verify SSL Certificates
```bash
# Check certificate status
kubectl get certificates -n production
kubectl describe certificate api-tls -n production

# Test HTTPS endpoint
curl -I https://api.yourdomain.com/health
```

### Step 5.4: Run Database Migrations
```bash
# Manual migration (first deployment)
kubectl exec -it deployment/api-production-web -n production -- php artisan migrate --force

# Or enable automatic migrations in values
# databaseMigration.enabled: true (already enabled)
```

### Step 5.5: Configure Backup Strategy
```bash
# Setup database backups (example for Azure Database for PostgreSQL)
az postgres server configuration set \
  --resource-group $RESOURCE_GROUP \
  --server-name your-postgres-server \
  --name backup_retention_days \
  --value 30

# Setup persistent volume backups
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: backup-script
  namespace: production
data:
  backup.sh: |
    #!/bin/bash
    pg_dump -h \$DB_HOST -U \$DB_USERNAME -d \$DB_DATABASE > /backup/backup-\$(date +%Y%m%d-%H%M%S).sql
EOF
```

## Troubleshooting

### Common Issues

#### 1. Pod ImagePullBackOff
```bash
# Check image pull secret
kubectl get secret ghcr-pull-secret -n production -o yaml

# Recreate if needed
kubectl delete secret ghcr-pull-secret -n production
kubectl create secret docker-registry ghcr-pull-secret \
  --namespace=production \
  --docker-server=ghcr.io \
  --docker-username=your-username \
  --docker-password=your-token
```

#### 2. Database Connection Issues
```bash
# Check database secrets
kubectl get secret api-secrets-prod -n production -o yaml

# Test database connectivity
kubectl run -it --rm debug --image=postgres:15-alpine --restart=Never -- psql -h your-db-host -U your-username -d your-database
```

#### 3. Certificate Issues
```bash
# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Check certificate status
kubectl describe certificate api-tls -n production

# Force certificate renewal
kubectl delete certificate api-tls -n production
```

#### 4. Ingress Not Working
```bash
# Check Traefik logs
kubectl logs -n traefik deployment/traefik

# Check ingress configuration
kubectl describe ingress -n production

# Test internal service
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- curl http://api-production-web.production.svc.cluster.local
```

### Useful Commands

```bash
# View all resources
kubectl get all -n production

# Check pod logs
kubectl logs deployment/api-production-web -n production

# Execute commands in pod
kubectl exec -it deployment/api-production-web -n production -- php artisan tinker

# Port forward for debugging
kubectl port-forward service/api-production-web -n production 8080:80

# Scale deployment
kubectl scale deployment api-production-web --replicas=3 -n production

# Check resource usage
kubectl top pods -n production
kubectl top nodes

# View events
kubectl get events -n production --sort-by='.lastTimestamp'
```

### Rollback Procedures

```bash
# Rollback Helm deployment
helm rollback api-production -n production

# Rollback Kubernetes deployment
kubectl rollout undo deployment/api-production-web -n production

# Check rollback status
kubectl rollout status deployment/api-production-web -n production
```

## Next Steps

1. **Security Hardening**: Implement Network Policies, Pod Security Standards
2. **Observability**: Setup distributed tracing, application metrics
3. **Disaster Recovery**: Implement cross-region backups and failover
4. **Performance**: Configure CDN, database read replicas
5. **Compliance**: Implement audit logging, data encryption at rest

## Support

- **Documentation**: Check individual component README files
- **Issues**: Create GitHub issues for bugs or feature requests
- **Community**: Join Kubernetes and Laravel communities for support

---

**Warning**: This setup includes production configurations. Always review security settings and credentials before deploying to production environments.