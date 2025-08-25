# Switching from GHCR to Azure Container Registry (ACR)

This document provides step-by-step instructions for switching from GitHub Container Registry (GHCR) back to Azure Container Registry (ACR). This might be necessary for various reasons such as organizational policies, compliance requirements, or integration preferences.

## Overview

This migration involves:
- Creating Azure Container Registry resources
- Updating Terraform configuration
- Modifying GitHub Actions workflows
- Updating Helm chart values
- Migrating existing container images
- Updating authentication mechanisms

## Prerequisites

- Azure CLI installed and configured
- Docker installed
- Access to existing GHCR images
- Azure subscription with appropriate permissions
- Terraform configured for your infrastructure

## Step 1: Create Azure Container Registry

### 1.1 Manual Creation (Quick Start)

```bash
# Set variables
RESOURCE_GROUP="monorepo-rg"
ACR_NAME="monorepocontainerregistry"  # Must be globally unique
LOCATION="East US"

# Create ACR
az acr create \
  --resource-group $RESOURCE_GROUP \
  --name $ACR_NAME \
  --sku Standard \
  --admin-enabled false \
  --location $LOCATION
```

### 1.2 Terraform Configuration (Recommended)

Add ACR resource back to `infrastructure/terraform/main.tf`:

```hcl
# Azure Container Registry
resource "azurerm_container_registry" "main" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  sku                = "Standard"
  admin_enabled      = false

  tags = var.tags
}

# Role assignment for AKS to pull from ACR
resource "azurerm_role_assignment" "aks_acr" {
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                           = azurerm_container_registry.main.id
  skip_service_principal_aad_check = true
}
```

## Step 2: Update Terraform Variables

### 2.1 Add ACR Variable

Update `infrastructure/terraform/variables.tf`:

```hcl
variable "acr_name" {
  description = "Azure Container Registry name"
  type        = string
  default     = "monorepocontainerregistry"
}
```

### 2.2 Update Environment Files

**Production (`infrastructure/terraform/environments/production.tfvars`):**
```hcl
resource_group_name = "monorepo-production-rg"
location           = "East US"
cluster_name       = "monorepo-production-aks"
acr_name          = "monorepoproduction"
node_count        = 3
node_vm_size      = "Standard_D2s_v3"
kubernetes_version = "1.28.3"
```

**Staging (`infrastructure/terraform/environments/staging.tfvars`):**
```hcl
resource_group_name = "monorepo-staging-rg"
location           = "East US"
cluster_name       = "monorepo-staging-aks"
acr_name          = "monorepostaging"
node_count        = 2
node_vm_size      = "Standard_B2s"
kubernetes_version = "1.28.3"
```

## Step 3: Remove GHCR Kubernetes Secrets

Update `infrastructure/terraform/main.tf` to remove GHCR pull secrets:

```hcl
# Remove these resources:
# - kubernetes_secret.ghcr_pull_secret
# - kubernetes_secret.ghcr_pull_secret_production  
# - kubernetes_secret.ghcr_pull_secret_staging

# Remove these variables from variables.tf:
# - github_username
# - github_token
# - github_email (unless used elsewhere)
```

## Step 4: Update GitHub Actions Workflows

### 4.1 API Workflow (`.github/workflows/ci-cd-api.yml`)

```yaml
env:
  REGISTRY: <YOUR_ACR_NAME>.azurecr.io
  IMAGE_NAME: api

# Replace GHCR login with ACR login
- name: Log in to Azure Container Registry
  uses: azure/docker-login@v1
  with:
    login-server: ${{ env.REGISTRY }}
    username: ${{ secrets.ACR_USERNAME }}
    password: ${{ secrets.ACR_PASSWORD }}
```

### 4.2 Frontend Workflow (`.github/workflows/ci-cd-frontend.yml`)

```yaml
env:
  REGISTRY: <YOUR_ACR_NAME>.azurecr.io
  IMAGE_NAME: frontend

# Replace GHCR login with ACR login
- name: Log in to Azure Container Registry
  uses: azure/docker-login@v1
  with:
    login-server: ${{ env.REGISTRY }}
    username: ${{ secrets.ACR_USERNAME }}
    password: ${{ secrets.ACR_PASSWORD }}
```

## Step 5: Update Helm Chart Values

### 5.1 API Charts

**`infrastructure/helm/api/values.yml`:**
```yaml
image:
  repository: <YOUR_ACR_NAME>.azurecr.io/api
  pullPolicy: IfNotPresent
  tag: latest

# Remove imagePullSecrets section (not needed with AKS-ACR integration)
```

**`infrastructure/helm/api/values-production.yml`:**
```yaml
image:
  repository: <YOUR_ACR_NAME>.azurecr.io/api
  pullPolicy: Always
  tag: latest

# Remove imagePullSecrets section
```

### 5.2 Frontend Charts

**`infrastructure/helm/frontend/values.yml`:**
```yaml
image:
  repository: <YOUR_ACR_NAME>.azurecr.io/frontend
  pullPolicy: IfNotPresent
  tag: latest

# Remove imagePullSecrets section
```

**`infrastructure/helm/frontend/values-production.yml`:**
```yaml
image:
  repository: <YOUR_ACR_NAME>.azurecr.io/frontend
  pullPolicy: Always
  tag: latest

# Remove imagePullSecrets section
```

## Step 6: Set Up ACR Authentication

### 6.1 Create Service Principal

```bash
# Create service principal for ACR access
ACR_NAME="<YOUR_ACR_NAME>"
SERVICE_PRINCIPAL_NAME="acr-service-principal"

# Get ACR resource ID
ACR_RESOURCE_ID=$(az acr show --name $ACR_NAME --query "id" --output tsv)

# Create service principal with AcrPush role
SP_DETAILS=$(az ad sp create-for-rbac \
  --name $SERVICE_PRINCIPAL_NAME \
  --role AcrPush \
  --scopes $ACR_RESOURCE_ID)

# Extract credentials
ACR_USERNAME=$(echo $SP_DETAILS | jq -r '.appId')
ACR_PASSWORD=$(echo $SP_DETAILS | jq -r '.password')

echo "ACR_USERNAME: $ACR_USERNAME"
echo "ACR_PASSWORD: $ACR_PASSWORD"
```

### 6.2 Update GitHub Secrets

Add these secrets to your GitHub repository:

- `ACR_USERNAME`: Service principal app ID
- `ACR_PASSWORD`: Service principal password

You can keep the existing `AZURE_CREDENTIALS` secret for AKS access.

## Step 7: Migrate Container Images

### 7.1 Pull Images from GHCR

```bash
# Set variables
GITHUB_USERNAME="<YOUR_GITHUB_USERNAME>"
REPO_NAME="<YOUR_REPO_NAME>"
ACR_NAME="<YOUR_ACR_NAME>"

# Pull images from GHCR
docker pull ghcr.io/$GITHUB_USERNAME/$REPO_NAME/api:latest
docker pull ghcr.io/$GITHUB_USERNAME/$REPO_NAME/frontend:latest

# Tag for ACR
docker tag ghcr.io/$GITHUB_USERNAME/$REPO_NAME/api:latest $ACR_NAME.azurecr.io/api:latest
docker tag ghcr.io/$GITHUB_USERNAME/$REPO_NAME/frontend:latest $ACR_NAME.azurecr.io/frontend:latest
```

### 7.2 Push Images to ACR

```bash
# Login to ACR
az acr login --name $ACR_NAME

# Push images
docker push $ACR_NAME.azurecr.io/api:latest
docker push $ACR_NAME.azurecr.io/frontend:latest

# Verify images
az acr repository list --name $ACR_NAME --output table
```

### 7.3 Automated Migration Script

Create `scripts/migrate-images.sh`:

```bash
#!/bin/bash
set -e

# Configuration
GITHUB_USERNAME="${GITHUB_USERNAME:-your-username}"
REPO_NAME="${REPO_NAME:-your-repo}"
ACR_NAME="${ACR_NAME:-your-acr-name}"

# Tags to migrate
TAGS=("latest" "main" "develop")

for tag in "${TAGS[@]}"; do
    echo "Migrating tag: $tag"
    
    # Pull from GHCR
    docker pull ghcr.io/$GITHUB_USERNAME/$REPO_NAME/api:$tag || echo "Tag $tag not found for api"
    docker pull ghcr.io/$GITHUB_USERNAME/$REPO_NAME/frontend:$tag || echo "Tag $tag not found for frontend"
    
    # Tag for ACR
    docker tag ghcr.io/$GITHUB_USERNAME/$REPO_NAME/api:$tag $ACR_NAME.azurecr.io/api:$tag || echo "Failed to tag api:$tag"
    docker tag ghcr.io/$GITHUB_USERNAME/$REPO_NAME/frontend:$tag $ACR_NAME.azurecr.io/frontend:$tag || echo "Failed to tag frontend:$tag"
    
    # Push to ACR
    docker push $ACR_NAME.azurecr.io/api:$tag || echo "Failed to push api:$tag"
    docker push $ACR_NAME.azurecr.io/frontend:$tag || echo "Failed to push frontend:$tag"
done

echo "Migration completed!"
```

## Step 8: Update Deployment Scripts

Update `scripts/deploy.sh`:

```bash
#!/bin/bash
# ... existing code ...

# Build and push images to ACR
echo "Building and pushing Docker images to Azure Container Registry..."

# Login to ACR
az acr login --name $ACR_NAME

docker build -t $ACR_NAME.azurecr.io/api:latest ./apps/api
docker build -t $ACR_NAME.azurecr.io/frontend:latest ./apps/frontend

docker push $ACR_NAME.azurecr.io/api:latest
docker push $ACR_NAME.azurecr.io/frontend:latest

# ... rest of deployment script ...
```

## Step 9: Deploy Updated Infrastructure

### 9.1 Plan and Apply Changes

```bash
cd infrastructure/terraform

# Initialize (in case new providers are needed)
terraform init

# Plan changes
terraform plan -var-file="environments/production.tfvars"

# Apply changes
terraform apply -var-file="environments/production.tfvars"
```

### 9.2 Verify ACR Integration

```bash
# Check AKS can access ACR
kubectl run test-pod --image=$ACR_NAME.azurecr.io/api:latest --rm -it -- /bin/sh

# If successful, the pod should start without image pull errors
```

## Step 10: Update Documentation

### 10.1 Update SECRETS.md

```markdown
# Required GitHub Secrets

Set up these secrets in your GitHub repository:

`AZURE_CREDENTIALS`: Service principal credentials for Azure
`ACR_USERNAME`: Azure Container Registry username (service principal app ID)
`ACR_PASSWORD`: Azure Container Registry password (service principal password)
```

### 10.2 Update README.md

Update references from GHCR to ACR:
- Container registry information
- Authentication methods
- Image repository URLs

## Step 11: Validation and Testing

### 11.1 Validation Checklist

- [ ] ACR resource created successfully
- [ ] AKS has AcrPull permissions on ACR
- [ ] GitHub Actions can authenticate with ACR
- [ ] Images build and push successfully
- [ ] Kubernetes pods can pull images from ACR
- [ ] Applications deploy successfully
- [ ] All endpoints are accessible

### 11.2 Test Deployment

```bash
# Test API deployment
helm upgrade --install api-production ./infrastructure/helm/api \
  -f ./infrastructure/helm/api/values-production.yml \
  -n production

# Test Frontend deployment  
helm upgrade --install frontend-production ./infrastructure/helm/frontend \
  -f ./infrastructure/helm/frontend/values-production.yml \
  -n production

# Check pod status
kubectl get pods -n production
```

## Step 12: Cleanup GHCR (Optional)

### 12.1 Delete GHCR Images

```bash
# List packages
gh api user/packages?package_type=container

# Delete packages (be careful!)
gh api --method DELETE /user/packages/container/api
gh api --method DELETE /user/packages/container/frontend
```

### 12.2 Remove GHCR References

- Remove GHCR migration documentation
- Clean up any GHCR-specific scripts
- Update CI/CD documentation

## Troubleshooting

### Common Issues

1. **ACR Authentication Errors**
   ```bash
   # Test ACR login
   az acr login --name $ACR_NAME
   
   # Check service principal permissions
   az role assignment list --assignee $ACR_USERNAME --scope $ACR_RESOURCE_ID
   ```

2. **Image Pull Errors in Kubernetes**
   ```bash
   # Check AKS-ACR integration
   kubectl describe pod <pod-name>
   
   # Verify role assignment
   az role assignment list --assignee $(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query identityProfile.kubeletidentity.objectId -o tsv)
   ```

3. **GitHub Actions Build Failures**
   - Verify ACR_USERNAME and ACR_PASSWORD secrets
   - Check service principal hasn't expired
   - Ensure ACR name is correct in workflows

### Useful Commands

```bash
# Check ACR repositories
az acr repository list --name $ACR_NAME

# Check image tags
az acr repository show-tags --name $ACR_NAME --repository api

# Test image pull
docker pull $ACR_NAME.azurecr.io/api:latest

# Check AKS identity
az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query identityProfile.kubeletidentity.objectId -o tsv
```

## Cost Considerations

### ACR Pricing
- **Basic**: $5/month + $0.10/GB storage + bandwidth costs
- **Standard**: $20/month + $0.10/GB storage + bandwidth costs  
- **Premium**: $500/month + enhanced features

### GHCR vs ACR Cost Comparison
- GHCR: Free for public repos, $0.25/GB for private repos
- ACR: Fixed monthly cost + storage + bandwidth
- Consider your usage patterns and organizational requirements

## Rollback Plan

If you need to rollback to GHCR:
1. Keep GHCR images as backup
2. Revert Terraform changes
3. Update GitHub Actions workflows back to GHCR
4. Update Helm values to use GHCR images
5. Redeploy applications

## Support Resources

- [Azure Container Registry Documentation](https://docs.microsoft.com/en-us/azure/container-registry/)
- [AKS Integration with ACR](https://docs.microsoft.com/en-us/azure/aks/cluster-container-registry-integration)
- [GitHub Actions Azure Login](https://github.com/Azure/login)
- [Docker Registry Authentication](https://docs.docker.com/registry/spec/auth/)

## Security Considerations

1. **Service Principal Management**
   - Rotate credentials regularly
   - Use least privilege principle
   - Monitor access logs

2. **Image Security**
   - Enable vulnerability scanning in ACR
   - Use signed images when possible
   - Implement image policies

3. **Network Security**
   - Consider private endpoints for ACR
   - Use Azure AD authentication when possible
   - Implement network access restrictions

This completes the migration from GHCR to Azure Container Registry. Test thoroughly before deploying to production environments.