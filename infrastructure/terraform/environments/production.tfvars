resource_group_name = "monorepo-production-rg"
location           = "East US"
cluster_name       = "monorepo-production-aks"
acr_name          = "monorepoproduction"
node_count        = 3
node_vm_size      = "Standard_D2s_v3"
kubernetes_version = "1.28.3"

tags = {
  Environment = "production"
  Project     = "monorepo"
  Owner       = "devops-team"
}