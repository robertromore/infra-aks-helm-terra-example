# Cloudflare Secret for cert-manager DNS01 challenge
resource "kubernetes_secret" "cloudflare_api_token" {
  metadata {
    name      = "cloudflare-api-token-secret"
    namespace = "cert-manager"
  }

  data = {
    api-token = var.cloudflare_api_token
  }

  type = "Opaque"

  depends_on = [helm_release.cert_manager]
}

# Let's Encrypt Staging ClusterIssuer with Cloudflare DNS01
resource "kubernetes_manifest" "letsencrypt_staging_cloudflare" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-staging"
    }
    spec = {
      acme = {
        email  = var.github_email
        server = "https://acme-staging-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-staging"
        }
        solvers = [
          {
            dns01 = {
              cloudflare = {
                apiTokenSecretRef = {
                  name = "cloudflare-api-token-secret"
                  key  = "api-token"
                }
              }
            }
            selector = {
              dnsZones = [var.domain_name]
            }
          }
        ]
      }
    }
  }

  depends_on = [
    helm_release.cert_manager,
    kubernetes_secret.cloudflare_api_token
  ]
}

# Let's Encrypt Production ClusterIssuer with Cloudflare DNS01
resource "kubernetes_manifest" "letsencrypt_prod_cloudflare" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        email  = var.github_email
        server = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-prod"
        }
        solvers = [
          {
            dns01 = {
              cloudflare = {
                apiTokenSecretRef = {
                  name = "cloudflare-api-token-secret"
                  key  = "api-token"
                }
              }
            }
            selector = {
              dnsZones = [var.domain_name]
            }
          }
        ]
      }
    }
  }

  depends_on = [
    helm_release.cert_manager,
    kubernetes_secret.cloudflare_api_token
  ]
}

# Wildcard certificate for the domain (optional)
resource "kubernetes_manifest" "wildcard_certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "wildcard-${replace(var.domain_name, ".", "-")}"
      namespace = "default"
    }
    spec = {
      secretName = "wildcard-${replace(var.domain_name, ".", "-")}-tls"
      issuerRef = {
        name = "letsencrypt-prod"
        kind = "ClusterIssuer"
      }
      dnsNames = [
        var.domain_name,
        "*.${var.domain_name}"
      ]
    }
  }

  depends_on = [kubernetes_manifest.letsencrypt_prod_cloudflare]
}

# Create wildcard certificate in production namespace
resource "kubernetes_manifest" "wildcard_certificate_production" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "wildcard-${replace(var.domain_name, ".", "-")}"
      namespace = "production"
    }
    spec = {
      secretName = "wildcard-${replace(var.domain_name, ".", "-")}-tls"
      issuerRef = {
        name = "letsencrypt-prod"
        kind = "ClusterIssuer"
      }
      dnsNames = [
        var.domain_name,
        "*.${var.domain_name}"
      ]
    }
  }

  depends_on = [kubernetes_manifest.letsencrypt_prod_cloudflare]
}

# Create wildcard certificate in staging namespace
resource "kubernetes_manifest" "wildcard_certificate_staging" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "wildcard-${replace(var.domain_name, ".", "-")}"
      namespace = "staging"
    }
    spec = {
      secretName = "wildcard-${replace(var.domain_name, ".", "-")}-tls"
      issuerRef = {
        name = "letsencrypt-prod"
        kind = "ClusterIssuer"
      }
      dnsNames = [
        var.domain_name,
        "*.${var.domain_name}"
      ]
    }
  }

  depends_on = [kubernetes_manifest.letsencrypt_prod_cloudflare]
}
