# Traefik Middlewares for API
resource "kubernetes_manifest" "api_headers_middleware" {
  manifest = {
    apiVersion = "traefik.containo.us/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "api-headers"
      namespace = "default"
    }
    spec = {
      headers = {
        customRequestHeaders = {
          "X-Forwarded-Proto" = "https"
        }
        customResponseHeaders = {
          "X-Content-Type-Options" = "nosniff"
          "X-Frame-Options"        = "DENY"
          "X-XSS-Protection"       = "1; mode=block"
        }
      }
    }
  }

  depends_on = [helm_release.traefik]
}

resource "kubernetes_manifest" "api_ratelimit_middleware" {
  manifest = {
    apiVersion = "traefik.containo.us/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "api-ratelimit"
      namespace = "default"
    }
    spec = {
      rateLimit = {
        average = 100
        period  = "1m"
        burst   = 200
      }
    }
  }

  depends_on = [helm_release.traefik]
}

# Traefik Middlewares for Frontend
resource "kubernetes_manifest" "frontend_headers_middleware" {
  manifest = {
    apiVersion = "traefik.containo.us/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "frontend-headers"
      namespace = "default"
    }
    spec = {
      headers = {
        customRequestHeaders = {
          "X-Forwarded-Proto" = "https"
        }
        customResponseHeaders = {
          "X-Content-Type-Options" = "nosniff"
          "X-Frame-Options"        = "SAMEORIGIN"
          "X-XSS-Protection"       = "1; mode=block"
        }
      }
    }
  }

  depends_on = [helm_release.traefik]
}

resource "kubernetes_manifest" "frontend_cors_middleware" {
  manifest = {
    apiVersion = "traefik.containo.us/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "frontend-cors"
      namespace = "default"
    }
    spec = {
      headers = {
        accessControlAllowMethods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
        accessControlAllowOriginList = ["*"]
        accessControlAllowHeaders = ["Content-Type", "Authorization", "X-Requested-With"]
        accessControlMaxAge = 86400
      }
    }
  }

  depends_on = [helm_release.traefik]
}

resource "kubernetes_manifest" "frontend_ratelimit_middleware" {
  manifest = {
    apiVersion = "traefik.containo.us/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "frontend-ratelimit"
      namespace = "default"
    }
    spec = {
      rateLimit = {
        average = 200
        period  = "1m"
        burst   = 400
      }
    }
  }

  depends_on = [helm_release.traefik]
}

# Global redirect middleware for HTTPS
resource "kubernetes_manifest" "https_redirect_middleware" {
  manifest = {
    apiVersion = "traefik.containo.us/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "https-redirect"
      namespace = "default"
    }
    spec = {
      redirectScheme = {
        scheme    = "https"
        permanent = true
      }
    }
  }

  depends_on = [helm_release.traefik]
}

# Body size middleware for API (equivalent to nginx proxy-body-size)
resource "kubernetes_manifest" "api_body_size_middleware" {
  manifest = {
    apiVersion = "traefik.containo.us/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "api-body-size"
      namespace = "default"
    }
    spec = {
      buffering = {
        maxRequestBodyBytes = 52428800  # 50MB
        memRequestBodyBytes = 10485760  # 10MB
      }
    }
  }

  depends_on = [helm_release.traefik]
}

resource "kubernetes_manifest" "frontend_body_size_middleware" {
  manifest = {
    apiVersion = "traefik.containo.us/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "frontend-body-size"
      namespace = "default"
    }
    spec = {
      buffering = {
        maxRequestBodyBytes = 10485760  # 10MB
        memRequestBodyBytes = 1048576   # 1MB
      }
    }
  }

  depends_on = [helm_release.traefik]
}
