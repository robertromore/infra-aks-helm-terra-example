# Infrastructure Setup with AKS, Helm, and Terraform

A complete infrastructure-as-code solution for deploying Laravel + Next.js applications on Azure Kubernetes Service (AKS) using Terraform, Helm, and GitHub Container Registry (GHCR).

## Features

- **Container Registry**: GitHub Container Registry (GHCR) for cost-effective image storage
- **Ingress Controller**: Traefik for advanced routing and middleware capabilities
- **Infrastructure as Code**: Terraform for Azure resource management
- **Application Deployment**: Helm charts for Kubernetes applications
- **CI/CD**: GitHub Actions workflows for automated testing and deployment
- **Monitoring**: Prometheus and Grafana integration
- **Security**: SSL/TLS certificates with cert-manager

## Prerequisites

- Azure CLI installed and configured
- Terraform >= 1.0
- kubectl configured
- Helm >= 3.0
- Docker
- GitHub account with repository access

## Setup Instructions

### 1. Fork/Clone Repository

```bash
git clone <your-repository-url>
cd infra-aks-helm-terra-example
```

### 2. Configure GitHub Container Registry

1. Update image repository references in Helm values files:
   - Replace `GITHUB_USERNAME` with your GitHub username
   - Replace `REPO_NAME` with your repository name

2. Ensure your repository has container registry enabled:
   - Go to repository Settings → Actions → General
   - Set "Workflow permissions" to "Read and write permissions"

### 3. Set up Azure Resources

```bash
# Create resource group for Terraform state
az group create --name terraform-state-rg --location "East US"

# Create storage account for Terraform state
az storage account create --resource-group terraform-state-rg --name tfstateaccount --sku Standard_LRS

# Create container for Terraform state
az storage container create --name tfstate --account-name tfstateaccount
```

### 4. Configure Terraform Variables

Create a `terraform.tfvars` file in `infrastructure/terraform/`:

```hcl
# Basic configuration
resource_group_name = "monorepo-rg"
location           = "East US"
cluster_name       = "monorepo-aks"

# GitHub Container Registry authentication
github_username = "your-github-username"
github_token    = "your-github-personal-access-token"
github_email    = "your-email@example.com"

# Cloudflare DNS configuration (for SSL certificates)
cloudflare_api_token = "your-cloudflare-api-token"
cloudflare_zone_id   = "your-cloudflare-zone-id"
domain_name          = "yourdomain.com"

# Optional: Customize cluster settings
node_count        = 2
node_vm_size      = "Standard_DS2_v2"
kubernetes_version = "1.28.3"
```

**Note**: For enhanced security, you can use environment variables instead of storing sensitive data in `terraform.tfvars`:

```bash
export TF_VAR_github_token="your-github-token"
export TF_VAR_cloudflare_api_token="your-cloudflare-token"
export TF_VAR_cloudflare_zone_id="your-zone-id"
```

### 5. Configure Cloudflare DNS (Required for SSL)

1. **Create Cloudflare API Token**:
   - Go to [Cloudflare Dashboard](https://dash.cloudflare.com/) → My Profile → API Tokens
   - Create a custom token with permissions:
     - Zone:Zone:Read
     - Zone:DNS:Edit
   - Include your specific zone in resources

2. **Get Zone ID**:
   - In Cloudflare Dashboard, select your domain
   - Copy the Zone ID from the right sidebar

3. **Update DNS Records**:
   After deployment, point your domain records to the load balancer IP

### 6. Deploy Infrastructure

```bash
cd infrastructure/terraform
terraform init
terraform plan
terraform apply
```

### 7. Configure GitHub Secrets

Set up these secrets in your GitHub repository (Settings → Secrets and variables → Actions):

- `AZURE_CREDENTIALS`: Service principal credentials for Azure
- `GITHUB_TOKEN`: Automatically available, or custom PAT with packages permissions

### 8. Deploy Applications

Push your code to trigger CI/CD pipelines, or deploy manually:

```bash
# Set environment variables
export GITHUB_USERNAME="your-github-username"
export GITHUB_TOKEN="your-github-token"
export ENVIRONMENT="production"  # or "staging"

# Run deployment script
./scripts/deploy.sh $ENVIRONMENT
```

## Architecture

### Container Images
- **Registry**: GitHub Container Registry (ghcr.io)
- **Images**: `ghcr.io/username/repo/api` and `ghcr.io/username/repo/frontend`
- **Authentication**: GitHub Personal Access Tokens

### Kubernetes Components
- **Ingress**: Traefik with custom middlewares
- **SSL/TLS**: cert-manager with Let's Encrypt and Cloudflare DNS validation
- **DNS**: Cloudflare DNS for domain management and SSL certificate challenges
- **Storage**: Azure managed disks for persistent volumes
- **Networking**: Azure CNI with network policies

### Monitoring Stack
- **Metrics**: Prometheus for metrics collection
- **Visualization**: Grafana dashboards
- **Logs**: Azure Log Analytics integration

## Migration Guides

### Container Registry Migration
- **[ACR to GHCR Migration](docs/ACR_TO_GHCR.md)**: Complete guide for migrating from Azure Container Registry to GitHub Container Registry
- **[GHCR to ACR Migration](docs/SWITCH_TO_ACR.md)**: Step-by-step guide for switching back to Azure Container Registry

### Ingress Controller Migration  
- **[nginx to Traefik Migration](docs/NGINX_TO_TRAEFIK.md)**: Comprehensive guide for migrating from nginx ingress to Traefik
- **[Traefik to nginx Migration](docs/TRAEFIK_TO_NGINX.md)**: Complete instructions for switching from Traefik to nginx ingress

### DNS and SSL Configuration
- **[Cloudflare DNS Setup](CLOUDFLARE_DNS.md)**: Guide for configuring Cloudflare DNS validation with cert-manager

## Directory Structure

```
├── .github/workflows/          # GitHub Actions CI/CD pipelines
├── apps/
│   ├── api/                   # Laravel API application
│   └── frontend/              # Next.js frontend application
├── infrastructure/
│   ├── helm/                  # Helm charts for applications
│   │   ├── api/
│   │   └── frontend/
│   └── terraform/             # Terraform infrastructure code
├── scripts/                   # Deployment and utility scripts
└── docs/                      # Additional documentation
```

## Key Benefits

### GitHub Container Registry
- **Cost Effective**: Free for public repos, competitive pricing for private
- **Native Integration**: Seamless GitHub Actions workflow
- **Security**: Built-in vulnerability scanning and access controls
- **Simplicity**: Single authentication mechanism

### Traefik Ingress
- **Performance**: Better resource efficiency than nginx
- **Flexibility**: Advanced routing and middleware system
- **Observability**: Built-in metrics and dashboard
- **Cloud Native**: Designed for Kubernetes environments

## Troubleshooting

### Common Issues

1. **Image Pull Errors**:
   ```bash
   kubectl get events --sort-by=.metadata.creationTimestamp
   kubectl describe pod <pod-name>
   ```

2. **Ingress Issues**:
   ```bash
   kubectl get ingress
   kubectl logs -n traefik-system deployment/traefik
   ```

3. **Certificate Problems**:
   ```bash
   kubectl get certificates
   kubectl describe certificate <cert-name>
   ```

4. **Cloudflare/DNS Issues**:
   ```bash
   # Check ClusterIssuer status
   kubectl describe clusterissuer letsencrypt-prod
   
   # Verify Cloudflare secret
   kubectl get secret cloudflare-api-token-secret -n cert-manager
   
   # Test DNS resolution
   dig api.yourdomain.com
   
   # Check certificate requests
   kubectl get certificaterequests -A
   ```

### Useful Commands

```bash
# Check cluster status
kubectl cluster-info

# View all resources
kubectl get all --all-namespaces

# Access Traefik dashboard
kubectl port-forward -n traefik-system svc/traefik 8080:8080

# Access Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:
- Check the troubleshooting section
- Review migration guides for specific topics
- Open an issue in the GitHub repository