# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.cluster_name}-logs"
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                = "PerGB2018"
  retention_in_days   = 30

  tags = var.tags
}

# Application Insights
resource "azurerm_application_insights" "main" {
  name                = "${var.cluster_name}-appinsights"
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id       = azurerm_log_analytics_workspace.main.id
  application_type   = "frontend"

  tags = var.tags
}

# Container Insights for AKS
# resource "azurerm_kubernetes_cluster" "main" {
#   # ... existing configuration ...

#   oms_agent {
#     log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
#   }

#   azure_policy_enabled = true
# }

# Prometheus and Grafana
resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = "monitoring"
  version    = "51.2.0"

  create_namespace = true

  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
          retention = "30d"
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                accessModes = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "50Gi"
                  }
                }
              }
            }
          }
        }
      }
      grafana = {
        adminPassword = "admin123"
        persistence = {
          enabled = true
          size = "10Gi"
        }
        ingress = {
          enabled = true
          ingressClassName = "traefik"
          hosts = ["grafana.${var.domain_name}"]
          tls = [{
            secretName = "grafana-tls"
            hosts = ["grafana.${var.domain_name}"]
          }]
        }
      }
    })
  ]

  depends_on = [azurerm_kubernetes_cluster.main]
}
