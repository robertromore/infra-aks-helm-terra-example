# Migrating from Azure Container Registry (ACR) to GitHub Container Registry (GHCR)

This document provides comprehensive step-by-step instructions for migrating from Azure Container Registry (ACR) to GitHub Container Registry (GHCR). This migration can help reduce costs, simplify authentication, and provide better integration with GitHub-based workflows.

## Overview

This migration involves:
- Removing Azure Container Registry resources
- Setting up GitHub Container Registry authentication
- Updating Terraform configuration
- Modifying GitHub Actions workflows
- Updating Helm chart values
- Migrating existing container images
- Implementing GHCR pull secrets for Kubernetes

## Why Migrate to GHCR?

### Benefits
- **Cost Reduction**: GHCR is free for public repositories and cost-effective for private repositories
- **Simplified Authentication**: Single GitHub token instead of separate Azure credentials
- **Native GitHub Integration**: Seamless workflow with GitHub Actions
- **Enhanced Security**: Built-in vulnerability scanning and access controls
- **Unified Platform**: Container images alongside source code

### Cost Comparison
| Feature | ACR (Standard) | GHCR |
|---------|----------------|------|
| Monthly Fee | $20 | Free for public |
| Storage (Private) | $0.10/GB | $0.25/GB (first 500MB free) |
| Bandwidth | Variable | Included |
| Public Images | Not applicable | Free |

## Prerequisites

- Access to existing ACR with container images
- GitHub repository with Actions enabled
- Azure CLI and kubectl installed
- Docker installed
- Terraform configured for your infrastructure
- Appropriate permissions on Azure subscription

## Step 1: Prepare GitHub Environment

### 1.1 Enable GitHub Container Registry

1. Navigate to your repository settings
2. Go to "Actions" → "General"
3. Under "Workflow permissions":
   - Select "Read and write permissions"
   - Check "Allow GitHub Actions to create and approve pull requests"

### 1.2 Create GitHub Personal Access Token (Optional)

For enhanced security or organization-level access:

1. Go to GitHub Settings → Developer settings → Personal access tokens
2. Create a token with these permissions:
   - `packages:read`
   - `packages:write`
   - `repo` (if repository is private)
3. Store the token securely

### 1.3 Update GitHub Repository Secrets

Remove ACR secrets and ensure GHCR access:

**Remove:**
- `ACR_USERNAME`
- `ACR_PASSWORD`

**Keep/Add:**
- `AZURE_CREDENTIALS` (still needed for AKS access)
- `GITHUB_TOKEN` (usually available by default)

## Step 2: Update Terraform Configuration

### 2.1 Remove ACR Resources

Edit `infrastructure/terraform/main.tf` to remove ACR components:

```hcl
# REMOVE these resources:

# resource "azurerm_container_registry" "main" {
#   name                = var.acr_name
#   resource_group_name = azurerm_resource_group.main.name
#   location           = azurerm_resource_group.main.location
#   sku                = "Standard"
#   admin_enabled      = false
#   tags = var.tags
# }

# resource "azurerm_role_assignment" "aks_acr" {
#   principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
#   role_definition_name             = "AcrPull"
#   scope                           = azurerm_container_registry.main.id
#   skip_service_principal_aad_check = true
# }
```

### 2.2 Add GHCR Kubernetes Secrets

Add GHCR pull secrets to `infrastructure/terraform/main.tf`:

```hcl
# GHCR Pull Secret for Kubernetes
resource "kubernetes_secret" "ghcr_pull_secret" {
  metadata {
    name      = "ghcr-pull-secret"
    namespace = "default"
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          username = var.github_username
          password = var.github_token
          email    = var.github_email
          auth     = base64encode("${var.github_username}:${var.github_token}")
        }
      }
    })
  }

  depends_on = [azurerm_kubernetes_cluster.main]
}

# Create pull secret in production namespace
resource "kubernetes_secret" "ghcr_pull_secret_production" {
  metadata {
    name      = "ghcr-pull-secret"
    namespace = "production"
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          username = var.github_username
          password = var.github_token
          email    = var.github_email
          auth     = base64encode("${var.github_username}:${var.github_token}")
        }
      }
    })
  }

  depends_on = [azurerm_kubernetes_cluster.main]
}

# Create pull secret in staging namespace
resource "kubernetes_secret" "ghcr_pull_secret_staging" {
  metadata {
    name      = "ghcr-pull-secret"
    namespace = "staging"
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          username = var.github_username
          password = var.github_token
          email    = var.github_email
          auth     = base64encode("${var.github_username}:${var.github_token}")
        }
      }
    })
  }

  depends_on = [azurerm_kubernetes_cluster.main]
}
```

### 2.3 Update Variables

Edit `infrastructure/terraform/variables.tf`:

```hcl
# REMOVE ACR variable:
# variable "acr_name" {
#   description = "Azure Container Registry name"
#   type        = string
#   default     = "monorepocontainerregistry"
# }

# ADD GitHub variables:
variable "github_username" {
  description = "GitHub username for GHCR access"
  type        = string
  sensitive   = true
}

variable "github_token" {
  description = "GitHub Personal Access Token for GHCR access"
  type        = string
  sensitive   = true
}

variable "github_email" {
  description = "GitHub email for GHCR access"
  type        = string
  sensitive   = true
}
```

### 2.4 Update Environment-Specific Variables

**Remove ACR references from `infrastructure/terraform/environments/production.tfvars`:**
```hcl
resource_group_name = "monorepo-production-rg"
location           = "East US"
cluster_name       = "monorepo-production-aks"
# acr_name          = "monorepoproduction"  # REMOVE this line
node_count        = 3
node_vm_size      = "Standard_D2s_v3"
kubernetes_version = "1.28.3"
```

**Do the same for `infrastructure/terraform/environments/staging.tfvars`**

## Step 3: Update GitHub Actions Workflows

### 3.1 Update API Workflow

Edit `.github/workflows/ci-cd-api.yml`:

```yaml
name: API CI/CD

on:
  push:
    branches: [main, develop]
    paths: ["apps/api/**", "infrastructure/helm/api/**"]
  pull_request:
    branches: [main]
    paths: ["apps/api/**", "infrastructure/helm/api/**"]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}/api

jobs:
  # ... existing test job remains the same ...

  build-and-push:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main' || github.ref == 'refs/heads/develop'

    steps:
      - uses: actions/checkout@v4

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch
            type=sha,prefix={{branch}}-

      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: ./apps/api
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}

  # ... rest of workflow remains the same ...
```

### 3.2 Update Frontend Workflow

Edit `.github/workflows/ci-cd-frontend.yml` with similar changes:

```yaml
name: Frontend CI/CD

# ... similar changes as API workflow ...

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}/frontend

# ... rest of the changes follow the same pattern as API workflow ...
```

## Step 4: Migrate Container Images

### 4.1 Create Migration Script

Create `scripts/migrate-acr-to-ghcr.sh`:

```bash
#!/bin/bash
set -e

# Configuration
ACR_NAME="${ACR_NAME:-your-acr-name}"
GITHUB_USERNAME="${GITHUB_USERNAME:-your-github-username}"
REPO_NAME="${REPO_NAME:-your-repo-name}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
if [[ -z "$ACR_NAME" || -z "$GITHUB_USERNAME" || -z "$REPO_NAME" ]]; then
    log_error "Please set ACR_NAME, GITHUB_USERNAME, and REPO_NAME environment variables"
    exit 1
fi

# Login to registries
log_info "Logging in to ACR..."
az acr login --name $ACR_NAME

log_info "Logging in to GHCR..."
if [[ -n "$GITHUB_TOKEN" ]]; then
    echo $GITHUB_TOKEN | docker login ghcr.io -u $GITHUB_USERNAME --password-stdin
else
    log_warning "GITHUB_TOKEN not set, using interactive login"
    docker login ghcr.io -u $GITHUB_USERNAME
fi

# Get list of repositories from ACR
log_info "Getting list of repositories from ACR..."
REPOSITORIES=$(az acr repository list --name $ACR_NAME --output tsv)

for REPO in $REPOSITORIES; do
    log_info "Processing repository: $REPO"
    
    # Get tags for this repository
    TAGS=$(az acr repository show-tags --name $ACR_NAME --repository $REPO --output tsv)
    
    for TAG in $TAGS; do
        log_info "Migrating $REPO:$TAG"
        
        # Pull from ACR
        ACR_IMAGE="$ACR_NAME.azurecr.io/$REPO:$TAG"
        GHCR_IMAGE="ghcr.io/$GITHUB_USERNAME/$REPO_NAME/$REPO:$TAG"
        
        docker pull $ACR_IMAGE
        docker tag $ACR_IMAGE $GHCR_IMAGE
        docker push $GHCR_IMAGE
        
        # Cleanup local images
        docker rmi $ACR_IMAGE $GHCR_IMAGE
        
        log_info "Successfully migrated $REPO:$TAG"
    done
done

log_info "Migration completed successfully!"
```

### 4.2 Run Migration

```bash
# Set environment variables
export ACR_NAME="your-acr-name"
export GITHUB_USERNAME="your-github-username"
export REPO_NAME="your-repo-name"
export GITHUB_TOKEN="your-github-token"  # Optional

# Make script executable and run
chmod +x scripts/migrate-acr-to-ghcr.sh
./scripts/migrate-acr-to-ghcr.sh
```

## Step 5: Update Helm Charts

### 5.1 Update API Helm Values

Edit `infrastructure/helm/api/values.yml`:

```yaml
image:
  repository: ghcr.io/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/api
  pullPolicy: IfNotPresent
  tag: latest

# Add image pull secrets
imagePullSecrets:
  - name: ghcr-pull-secret

# ... rest of configuration remains the same ...
```

Edit `infrastructure/helm/api/values-production.yml`:

```yaml
image:
  repository: ghcr.io/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/api
  pullPolicy: Always
  tag: latest

# Add image pull secrets
imagePullSecrets:
  - name: ghcr-pull-secret

# ... rest of configuration remains the same ...
```

### 5.2 Update Frontend Helm Values

Make similar changes to:
- `infrastructure/helm/frontend/values.yml`
- `infrastructure/helm/frontend/values-production.yml`

Replace `YOUR_GITHUB_USERNAME` and `YOUR_REPO_NAME` with actual values.

## Step 6: Update Deployment Scripts

Edit `scripts/deploy.sh`:

```bash
#!/bin/bash
# ... existing code ...

# Build and push images to GHCR
echo "Building and pushing Docker images to GitHub Container Registry..."

# Login to GHCR
echo $GITHUB_TOKEN | docker login ghcr.io -u $GITHUB_USERNAME --password-stdin

# Get repository name (assumes script is run from repo root)
REPO_NAME=$(basename -s .git $(git config --get remote.origin.url) 2>/dev/null || echo "your-repo-name")

docker build -t ghcr.io/$GITHUB_USERNAME/$REPO_NAME/api:latest ./apps/api
docker build -t ghcr.io/$GITHUB_USERNAME/$REPO_NAME/frontend:latest ./apps/frontend

docker push ghcr.io/$GITHUB_USERNAME/$REPO_NAME/api:latest
docker push ghcr.io/$GITHUB_USERNAME/$REPO_NAME/frontend:latest

# ... rest of deployment script ...
```

## Step 7: Update Terraform Variables File

Create or update `terraform.tfvars`:

```hcl
# Basic Azure Configuration (keep existing values)
resource_group_name = "monorepo-rg"
location           = "East US"
cluster_name       = "monorepo-aks"

# GitHub Container Registry Configuration (NEW)
github_username = "your-github-username"
github_token    = "your-github-personal-access-token"
github_email    = "your-email@example.com"

# Cloudflare DNS Configuration (if applicable)
cloudflare_api_token = "your-cloudflare-api-token"
cloudflare_zone_id   = "your-cloudflare-zone-id"
domain_name          = "yourdomain.com"

# Kubernetes Cluster Configuration (keep existing)
node_count        = 2
node_vm_size      = "Standard_DS2_v2"
kubernetes_version = "1.28.3"
```

## Step 8: Deploy Changes

### 8.1 Apply Terraform Changes

```bash
cd infrastructure/terraform

# Initialize if needed
terraform init

# Plan the changes
terraform plan

# Apply the changes
terraform apply
```

### 8.2 Update Helm Deployments

```bash
# Update API deployment
helm upgrade --install api ./infrastructure/helm/api \
  --namespace production \
  --values ./infrastructure/helm/api/values-production.yml

# Update Frontend deployment
helm upgrade --install frontend ./infrastructure/helm/frontend \
  --namespace production \
  --values ./infrastructure/helm/frontend/values-production.yml
```

## Step 9: Validation and Testing

### 9.1 Verify GHCR Images

```bash
# Check if images are available in GHCR
curl -H "Authorization: Bearer $GITHUB_TOKEN" \
  "https://ghcr.io/v2/$GITHUB_USERNAME/$REPO_NAME/api/tags/list"

# List all packages
gh api user/packages?package_type=container
```

### 9.2 Verify Kubernetes Deployment

```bash
# Check pod status
kubectl get pods -n production

# Check if images are pulled successfully
kubectl describe pod <pod-name> -n production

# Verify pull secrets
kubectl get secret ghcr-pull-secret -n production -o yaml
```

### 9.3 Test Application Endpoints

```bash
# Test API endpoint
curl -k https://api.yourdomain.com/health

# Test frontend
curl -k https://app.yourdomain.com
```

## Step 10: Cleanup ACR (Optional)

### 10.1 Backup Images (Recommended)

Before deleting ACR, ensure all images are successfully migrated:

```bash
# List ACR repositories one final time
az acr repository list --name $ACR_NAME

# Export image manifests for backup
for repo in $(az acr repository list --name $ACR_NAME --output tsv); do
  az acr repository show-manifests --name $ACR_NAME --repository $repo > "${repo}-manifests-backup.json"
done
```

### 10.2 Delete ACR Resources

```bash
# Delete ACR (be very careful!)
az acr delete --name $ACR_NAME --resource-group $RESOURCE_GROUP_NAME --yes

# Remove from Terraform state (if managed by Terraform)
terraform state rm azurerm_container_registry.main
terraform state rm azurerm_role_assignment.aks_acr
```

## Troubleshooting

### Common Issues

1. **Image Pull Errors**
   ```bash
   # Check pull secret exists and is correct
   kubectl get secret ghcr-pull-secret -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq
   
   # Verify GitHub token has correct permissions
   curl -H "Authorization: Bearer $GITHUB_TOKEN" https://api.github.com/user
   ```

2. **Authentication Failures in GitHub Actions**
   - Ensure repository has "Read and write permissions" enabled
   - Verify GITHUB_TOKEN is available in workflow
   - Check if organization has package restrictions

3. **Terraform Apply Failures**
   ```bash
   # Check AKS cluster status
   az aks show --name $CLUSTER_NAME --resource-group $RESOURCE_GROUP_NAME
   
   # Verify kubectl connectivity
   kubectl cluster-info
   ```

### Useful Commands

```bash
# Test image pull manually
docker pull ghcr.io/$GITHUB_USERNAME/$REPO_NAME/api:latest

# Check GHCR package visibility
gh api repos/$GITHUB_USERNAME/$REPO_NAME/packages

# Debug Kubernetes pull secrets
kubectl create secret docker-registry test-secret \
  --docker-server=ghcr.io \
  --docker-username=$GITHUB_USERNAME \
  --docker-password=$GITHUB_TOKEN \
  --dry-run=client -o yaml
```

## Security Considerations

1. **Token Management**
   - Use fine-grained personal access tokens when possible
   - Rotate tokens regularly
   - Monitor token usage in audit logs

2. **Image Visibility**
   - Consider making images public if possible to avoid pull authentication
   - Use private images only when necessary
   - Implement proper access controls

3. **Kubernetes Secrets**
   - Regularly rotate pull secrets
   - Use namespace-specific secrets
   - Monitor secret access

## Cost Optimization

1. **Image Management**
   - Set up retention policies for old image versions
   - Use multi-stage Docker builds to reduce image size
   - Implement image layer caching

2. **Usage Monitoring**
   - Monitor package storage usage
   - Track bandwidth usage patterns
   - Optimize for free tier limits

## Rollback Plan

If issues occur, you can rollback to ACR:

1. **Restore ACR Resources**
   ```bash
   terraform apply -target=azurerm_container_registry.main
   ```

2. **Update Image References**
   - Revert Helm values to use ACR URLs
   - Update GitHub Actions workflows

3. **Restore GitHub Secrets**
   - Add back ACR_USERNAME and ACR_PASSWORD
   - Update workflow authentication

4. **Redeploy Applications**
   ```bash
   helm upgrade --install api ./infrastructure/helm/api \
     --values values-with-acr.yml
   ```

## Next Steps

1. **Monitor Performance**: Compare image pull times between ACR and GHCR
2. **Implement Security Scanning**: Configure GitHub's vulnerability scanning
3. **Optimize Workflows**: Use GitHub Actions caching for better performance
4. **Set Up Monitoring**: Monitor package usage and costs
5. **Documentation**: Update all references from ACR to GHCR in documentation

## Resources

- [GitHub Container Registry Documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [GitHub Actions Docker Login](https://github.com/docker/login-action)
- [Kubernetes Image Pull Secrets](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/)
- [Azure Container Registry Migration](https://docs.microsoft.com/en-us/azure/container-registry/)

This completes the migration from Azure Container Registry to GitHub Container Registry. Monitor the deployment closely and ensure all applications function correctly before considering the migration complete.