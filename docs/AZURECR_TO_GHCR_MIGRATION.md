# GitHub Container Registry (GHCR) Migration Guide

This document outlines the migration from Azure Container Registry (ACR) to GitHub Container Registry (GHCR) for the AKS infrastructure project.

## Overview

The project has been migrated from Azure Container Registry to GitHub Container Registry for the following benefits:

- **Cost Efficiency**: GHCR is free for public repositories and has generous limits for private repositories
- **Simplified Authentication**: Uses GitHub tokens instead of managing separate Azure credentials
- **Better Integration**: Native integration with GitHub Actions workflows
- **Unified Platform**: Keep code and container images in the same ecosystem
- **Enhanced Security**: Leverages GitHub's security features and vulnerability scanning

## Changes Made

### 1. GitHub Actions Workflows

#### Before (ACR):
```yaml
env:
  REGISTRY: monorepocontainerregistry.azurecr.io
  IMAGE_NAME: api

- name: Log in to Azure Container Registry
  uses: azure/docker-login@v1
  with:
    login-server: ${{ env.REGISTRY }}
    username: ${{ secrets.ACR_USERNAME }}
    password: ${{ secrets.ACR_PASSWORD }}
```

#### After (GHCR):
```yaml
env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}/api

- name: Log in to GitHub Container Registry
  uses: docker/login-action@v3
  with:
    registry: ${{ env.REGISTRY }}
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}
```

### 2. Container Image References

All Helm values files have been updated to use GHCR:

#### Before:
```yaml
image:
  repository: monorepocontainerregistry.azurecr.io/api
```

#### After:
```yaml
image:
  repository: ghcr.io/GITHUB_USERNAME/REPO_NAME/api
imagePullSecrets:
  - name: ghcr-pull-secret
```

### 3. Terraform Infrastructure Changes

#### Removed:
- Azure Container Registry resource
- ACR role assignments
- ACR-related variables

#### Added:
- Kubernetes secrets for GHCR authentication
- GitHub-related variables for authentication

### 4. Authentication Mechanism

#### ACR (Old):
- Required Azure service principal
- Separate username/password secrets
- Azure role-based access control

#### GHCR (New):
- Uses GitHub Personal Access Token
- Leverages existing GitHub authentication
- Kubernetes pull secrets for cluster access

## Migration Steps

### 1. Update Repository Settings

1. **Enable GitHub Container Registry** (if not already enabled):
   - Go to your repository settings
   - Navigate to "Actions" → "General"
   - Ensure "Read and write permissions" is enabled for GITHUB_TOKEN

2. **Create GitHub Personal Access Token** (if using private images):
   - Go to GitHub Settings → Developer settings → Personal access tokens
   - Create a token with `packages:read` and `packages:write` permissions
   - Store as `GITHUB_TOKEN` secret (if different from default)

### 2. Update Image References

Replace all instances of ACR references with GHCR:

```bash
# Find and replace in Helm values
find infrastructure/helm -name "*.yml" -exec sed -i 's/monorepocontainerregistry\.azurecr\.io/ghcr.io\/GITHUB_USERNAME\/REPO_NAME/g' {} \;
```

**Note**: Replace `GITHUB_USERNAME` and `REPO_NAME` with your actual GitHub username and repository name.

### 3. Deploy Updated Infrastructure

```bash
# Set environment variables for Terraform
export TF_VAR_github_username="your-github-username"
export TF_VAR_github_token="your-github-token"
export TF_VAR_github_email="your-email@example.com"

# Deploy infrastructure
cd infrastructure/terraform
terraform plan
terraform apply
```

### 4. Build and Push Initial Images

```bash
# Set environment variables
export GITHUB_USERNAME="your-github-username"
export GITHUB_TOKEN="your-github-token"

# Run the deployment script
./scripts/deploy.sh production
```

### 5. Verify Deployment

```bash
# Check if images are available in GHCR
curl -H "Authorization: Bearer $GITHUB_TOKEN" \
     https://ghcr.io/v2/$GITHUB_USERNAME/$REPO_NAME/api/tags/list

# Verify Kubernetes can pull images
kubectl get pods -n production
kubectl describe pod <pod-name> -n production
```

## Required Secrets and Variables

### GitHub Repository Secrets
- `AZURE_CREDENTIALS`: Azure service principal (still needed for AKS access)
- `GITHUB_TOKEN`: Automatically available, or custom PAT if needed

### Terraform Variables
Create a `terraform.tfvars` file or set environment variables:

```hcl
github_username = "your-github-username"
github_token    = "your-github-token"
github_email    = "your-email@example.com"
```

### Environment Variables for Scripts
```bash
export GITHUB_USERNAME="your-github-username"
export GITHUB_TOKEN="your-github-token"
export REPO_NAME="your-repo-name"
```

## Container Image Visibility

### Public Images
- No authentication required for pulling
- Images are publicly accessible
- Free tier includes unlimited bandwidth

### Private Images
- Require authentication for pulling
- Use GitHub PAT or fine-grained tokens
- Subject to GitHub's pricing for private packages

## Benefits Achieved

1. **Cost Reduction**: Eliminated Azure Container Registry costs
2. **Simplified Authentication**: One less set of credentials to manage
3. **Better Security**: Leverage GitHub's security scanning and policies
4. **Native Integration**: Seamless workflow with GitHub Actions
5. **Unified Management**: Container images alongside source code

## Troubleshooting

### Common Issues

1. **Authentication Errors**
   ```bash
   # Verify GHCR login
   echo $GITHUB_TOKEN | docker login ghcr.io -u $GITHUB_USERNAME --password-stdin
   ```

2. **Image Pull Errors in Kubernetes**
   ```bash
   # Check if pull secret exists
   kubectl get secrets ghcr-pull-secret -o yaml
   
   # Verify secret is correctly formatted
   kubectl get secret ghcr-pull-secret -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d
   ```

3. **Permission Denied**
   - Ensure GitHub token has `packages:read` and `packages:write` permissions
   - Verify repository has container registry enabled
   - Check if organization has package restrictions

### Useful Commands

```bash
# List images in GHCR
curl -H "Authorization: Bearer $GITHUB_TOKEN" \
     https://api.github.com/user/packages?package_type=container

# Delete old ACR resources (if no longer needed)
az acr delete --name monorepocontainerregistry --resource-group monorepo-rg

# Test image pull manually
docker pull ghcr.io/$GITHUB_USERNAME/$REPO_NAME/api:latest
```

## Rollback Plan

If issues arise, you can rollback by:

1. **Revert Terraform changes**: Re-add ACR resources
2. **Update image references**: Change back to ACR URLs
3. **Restore GitHub Actions**: Use ACR authentication
4. **Update secrets**: Add back ACR credentials

Keep backup copies of the old configuration until migration is confirmed successful.

## Next Steps

1. **Monitor Performance**: Compare image pull times and reliability
2. **Set up Vulnerability Scanning**: Configure GitHub security features
3. **Optimize Image Sizes**: Use multi-stage builds and layer caching
4. **Implement Image Signing**: Consider using Sigstore/Cosign for image signing
5. **Package Cleanup**: Set up retention policies for old image versions

## Security Considerations

1. **Token Management**: Rotate GitHub tokens regularly
2. **Least Privilege**: Use fine-grained tokens when possible
3. **Image Scanning**: Enable GitHub's vulnerability scanning
4. **Access Control**: Review who has access to push/pull images
5. **Audit Logging**: Monitor package access logs

## Cost Comparison

### ACR (Previous)
- Standard SKU: ~$5/month
- Storage: ~$0.10/GB/month
- Bandwidth: Varies by region

### GHCR (Current)
- Private repositories: First 500MB free, then $0.25/GB/month
- Public repositories: Free
- Bandwidth: Included

The migration typically results in significant cost savings, especially for smaller projects.