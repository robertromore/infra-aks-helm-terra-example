resource_group_name = "monorepo-staging-rg"
location           = "East US"
cluster_name       = "monorepo-staging-aks"
node_count        = 2
node_vm_size      = "Standard_B2s"
kubernetes_version = "1.28.3"

# Domain and Cloudflare configuration
domain_name = "staging.yourcompany.com"
# Set these via environment variables or uncomment and set values:
# cloudflare_api_token = "your-cloudflare-api-token"
# cloudflare_zone_id = "your-cloudflare-zone-id"

tags = {
  Environment = "staging"
  Project     = "monorepo"
}
