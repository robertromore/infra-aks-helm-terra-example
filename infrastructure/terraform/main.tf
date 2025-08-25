resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = var.tags
}

# Note: Using GitHub Container Registry (GHCR) instead of Azure Container Registry
# GHCR authentication is handled via Kubernetes secrets in the applications

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "${var.cluster_name}-vnet"
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space      = ["10.1.0.0/16"]

  tags = var.tags
}

# Subnet for AKS
resource "azurerm_subnet" "aks" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.1.0.0/22"]
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix         = var.cluster_name
  kubernetes_version = var.kubernetes_version

  default_node_pool {
    name           = "default"
    node_count     = var.node_count
    vm_size        = var.node_vm_size
    vnet_subnet_id = azurerm_subnet.aks.id

    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }

  tags = var.tags
}

# GHCR Pull Secret for Kubernetes
resource "kubernetes_secret" "ghcr_pull_secret" {
  metadata {
    name      = "ghcr-pull-secret"
    namespace = "default"
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          username = var.github_username
          password = var.github_token
          email    = var.github_email
          auth     = base64encode("${var.github_username}:${var.github_token}")
        }
      }
    })
  }

  depends_on = [azurerm_kubernetes_cluster.main]
}

# Create pull secret in production namespace
resource "kubernetes_secret" "ghcr_pull_secret_production" {
  metadata {
    name      = "ghcr-pull-secret"
    namespace = "production"
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          username = var.github_username
          password = var.github_token
          email    = var.github_email
          auth     = base64encode("${var.github_username}:${var.github_token}")
        }
      }
    })
  }

  depends_on = [azurerm_kubernetes_cluster.main]
}

# Create pull secret in staging namespace
resource "kubernetes_secret" "ghcr_pull_secret_staging" {
  metadata {
    name      = "ghcr-pull-secret"
    namespace = "staging"
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          username = var.github_username
          password = var.github_token
          email    = var.github_email
          auth     = base64encode("${var.github_username}:${var.github_token}")
        }
      }
    })
  }

  depends_on = [azurerm_kubernetes_cluster.main]
}

# Traefik Ingress Controller
resource "helm_release" "traefik" {
  name       = "traefik"
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  namespace  = "traefik-system"
  version    = "25.0.0"

  create_namespace = true

  set {
    name  = "service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "ports.web.port"
    value = "80"
  }

  set {
    name  = "ports.websecure.port"
    value = "443"
  }

  set {
    name  = "ports.websecure.tls.enabled"
    value = "true"
  }

  set {
    name  = "providers.kubernetesIngress.ingressClass"
    value = "traefik"
  }

  set {
    name  = "globalArguments[0]"
    value = "--global.checknewversion=false"
  }

  set {
    name  = "globalArguments[1]"
    value = "--global.sendanonymoususage=false"
  }

  depends_on = [azurerm_kubernetes_cluster.main]
}

# Cert-Manager
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"
  version    = "v1.13.0"

  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [azurerm_kubernetes_cluster.main]
}
