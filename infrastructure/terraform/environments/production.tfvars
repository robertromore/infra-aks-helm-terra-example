resource_group_name = "monorepo-production-rg"
location           = "East US"
cluster_name       = "monorepo-production-aks"
node_count        = 3
node_vm_size      = "Standard_D2s_v3"
kubernetes_version = "1.28.3"

# Domain and Cloudflare configuration
domain_name = "yourcompany.com"
# Set these via environment variables or uncomment and set values:
# cloudflare_api_token = "your-cloudflare-api-token"
# cloudflare_zone_id = "your-cloudflare-zone-id"

tags = {
  Environment = "production"
  Project     = "monorepo"
}
