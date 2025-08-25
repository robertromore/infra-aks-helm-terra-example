# Setup Instructions

1. Fork/clone this repository
2. Set up Azure resources:

```bash
# Create resource group for Terraform state
az group create --name terraform-state-rg --location "East US"

# Create storage account for Terraform state
az storage account create --resource-group terraform-state-rg --name tfstateaccount --sku Standard_LRS

# Create container for Terraform state
az storage container create --name tfstate --account-name tfstateaccount
```

3. Deploy Infrastructure

```bash
cd infrastructure/terraform
terraform init
terraform plan
terraform apply
```

4. Push your code to trigger CI/CD pipelines

This setup provides a complete infrastructure foundation for a Laravel + Next.js monorepo with proper CI/CD, container orchestration, and cloud-native deployment patterns using Traefik ingress controller.
