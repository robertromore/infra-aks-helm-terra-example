resource_group_name = "monorepo-staging-rg"
location           = "East US"
cluster_name       = "monorepo-staging-aks"
acr_name          = "monorepostaging"
node_count        = 2
node_vm_size      = "Standard_B2s"
kubernetes_version = "1.28.3"

tags = {
  Environment = "staging"
  Project     = "monorepo"
  Owner       = "devops-team"
}