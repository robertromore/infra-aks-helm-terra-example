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

# Optional: Customize cluster settings
node_count        = 2
node_vm_size      = "Standard_DS2_v2"
kubernetes_version = "1.28.3"
```

### 5. Deploy Infrastructure

```bash
cd infrastructure/terraform
terraform init
terraform plan
terraform apply
```

### 6. Configure GitHub Secrets

Set up these secrets in your GitHub repository (Settings → Secrets and variables → Actions):

- `AZURE_CREDENTIALS`: Service principal credentials for Azure
- `GITHUB_TOKEN`: Automatically available, or custom PAT with packages permissions

### 7. Deploy Applications

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
- **SSL/TLS**: cert-manager with Let's Encrypt
- **Storage**: Azure managed disks for persistent volumes
- **Networking**: Azure CNI with network policies

### Monitoring Stack
- **Metrics**: Prometheus for metrics collection
- **Visualization**: Grafana dashboards
- **Logs**: Azure Log Analytics integration

## Migration Guides

- **[Traefik Migration](TRAEFIK_MIGRATION.md)**: Details about nginx to Traefik migration
- **[GHCR Migration](GHCR_MIGRATION.md)**: Complete guide for ACR to GHCR migration

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