# Migrating from nginx Ingress to Traefik Ingress

This document provides comprehensive step-by-step instructions for migrating from nginx ingress controller to Traefik ingress controller on Azure Kubernetes Service (AKS). This migration can provide better performance, advanced routing capabilities, and enhanced observability features.

## Overview

This migration involves:
- Removing nginx ingress controller resources
- Installing Traefik ingress controller
- Converting nginx annotations to Traefik middlewares
- Updating ingress resources and configurations
- Migrating SSL/TLS certificate configurations
- Testing and validating the new setup

## Why Migrate to Traefik?

### Benefits
- **Better Performance**: More efficient resource utilization and faster request processing
- **Advanced Routing**: Flexible routing rules with middleware support
- **Cloud-Native Design**: Built specifically for containerized environments
- **Enhanced Observability**: Built-in metrics, tracing, and dashboard
- **Dynamic Configuration**: Automatic service discovery and configuration updates
- **Middleware System**: Modular approach to request processing (auth, rate limiting, CORS, etc.)

### Feature Comparison
| Feature | nginx Ingress | Traefik |
|---------|---------------|---------|
| Performance | Good | Excellent |
| Configuration | Annotations | Middlewares + Annotations |
| Dashboard | Basic | Advanced with real-time metrics |
| Service Discovery | Static | Dynamic |
| Middleware Support | Limited | Extensive |
| Cloud-Native | Adapted | Native |

## Prerequisites

- Existing AKS cluster with nginx ingress controller
- kubectl configured and accessible
- Helm 3.x installed
- Terraform configured (if using IaC)
- Administrative access to DNS provider
- Backup of current ingress configurations

## Step 1: Audit Current nginx Configuration

### 1.1 Document Existing Ingresses

```bash
# List all ingresses
kubectl get ingress --all-namespaces -o wide

# Export ingress configurations
kubectl get ingress --all-namespaces -o yaml > nginx-ingress-backup.yaml

# Document nginx-specific annotations
grep -r "nginx.ingress.kubernetes.io" . --include="*.yaml" --include="*.yml"
```

### 1.2 Identify nginx-Specific Features

Common nginx annotations to convert:
- `nginx.ingress.kubernetes.io/rewrite-target`
- `nginx.ingress.kubernetes.io/ssl-redirect`
- `nginx.ingress.kubernetes.io/proxy-body-size`
- `nginx.ingress.kubernetes.io/rate-limit`
- `nginx.ingress.kubernetes.io/cors-allow-origin`
- `nginx.ingress.kubernetes.io/auth-*`

### 1.3 Check nginx Ingress Controller Status

```bash
# Check nginx controller pods
kubectl get pods -n ingress-nginx

# Check nginx controller service
kubectl get service -n ingress-nginx

# Get load balancer IP
kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

## Step 2: Install Traefik Ingress Controller

### 2.1 Terraform Configuration

Update `infrastructure/terraform/main.tf`:

```hcl
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

  # Enable dashboard
  set {
    name  = "ingressRoute.dashboard.enabled"
    value = "true"
  }

  # Enable API
  set {
    name  = "api.dashboard"
    value = "true"
  }

  set {
    name  = "api.debug"
    value = "true"
  }

  depends_on = [azurerm_kubernetes_cluster.main]
}
```

### 2.2 Manual Installation with Helm

```bash
# Add Traefik Helm repository
helm repo add traefik https://traefik.github.io/charts
helm repo update

# Install Traefik
helm install traefik traefik/traefik \
  --namespace traefik-system \
  --create-namespace \
  --set service.type=LoadBalancer \
  --set ports.web.port=80 \
  --set ports.websecure.port=443 \
  --set ports.websecure.tls.enabled=true \
  --set providers.kubernetesIngress.ingressClass=traefik \
  --set ingressRoute.dashboard.enabled=true \
  --set api.dashboard=true
```

### 2.3 Verify Traefik Installation

```bash
# Check Traefik pods
kubectl get pods -n traefik-system

# Check Traefik service
kubectl get service -n traefik-system

# Access Traefik dashboard (port-forward)
kubectl port-forward -n traefik-system svc/traefik 8080:8080
# Visit http://localhost:8080
```

## Step 3: Create Traefik Middlewares

### 3.1 Create Middleware Resources

Create `infrastructure/traefik-middlewares.yaml`:

```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: default-headers
  namespace: default
spec:
  headers:
    customRequestHeaders:
      X-Forwarded-Proto: "https"
    customResponseHeaders:
      X-Content-Type-Options: "nosniff"
      X-Frame-Options: "DENY"
      X-XSS-Protection: "1; mode=block"
      Referrer-Policy: "strict-origin-when-cross-origin"

---
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: secure-headers
  namespace: default
spec:
  headers:
    accessControlAllowMethods:
      - GET
      - POST
      - PUT
      - DELETE
      - PATCH
      - OPTIONS
    accessControlAllowOriginList:
      - "*"
    accessControlAllowHeaders:
      - "*"
    accessControlMaxAge: 100
    addVaryHeader: true

---
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: rate-limit
  namespace: default
spec:
  rateLimit:
    average: 100
    period: 1m
    burst: 200

---
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: body-size-limit
  namespace: default
spec:
  buffering:
    maxRequestBodyBytes: 52428800  # 50MB
    memRequestBodyBytes: 10485760  # 10MB

---
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: https-redirect
  namespace: default
spec:
  redirectScheme:
    scheme: https
    permanent: true

---
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: compress
  namespace: default
spec:
  compress: {}

---
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: strip-prefix
  namespace: default
spec:
  stripPrefix:
    prefixes:
      - "/api"
```

Apply middlewares:

```bash
kubectl apply -f infrastructure/traefik-middlewares.yaml
```

### 3.2 Terraform-Managed Middlewares

Add to `infrastructure/terraform/traefik-middlewares.tf`:

```hcl
# Default headers middleware
resource "kubernetes_manifest" "default_headers_middleware" {
  manifest = {
    apiVersion = "traefik.containo.us/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "default-headers"
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
          "Referrer-Policy"        = "strict-origin-when-cross-origin"
        }
      }
    }
  }
  depends_on = [helm_release.traefik]
}

# Rate limiting middleware
resource "kubernetes_manifest" "rate_limit_middleware" {
  manifest = {
    apiVersion = "traefik.containo.us/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "rate-limit"
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

# Body size limit middleware
resource "kubernetes_manifest" "body_size_middleware" {
  manifest = {
    apiVersion = "traefik.containo.us/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "body-size-limit"
      namespace = "default"
    }
    spec = {
      buffering = {
        maxRequestBodyBytes = 52428800
        memRequestBodyBytes = 10485760
      }
    }
  }
  depends_on = [helm_release.traefik]
}
```

## Step 4: Convert Ingress Resources

### 4.1 Annotation Mapping Guide

| nginx Annotation | Traefik Equivalent |
|------------------|-------------------|
| `kubernetes.io/ingress.class: nginx` | `kubernetes.io/ingress.class: traefik` |
| `nginx.ingress.kubernetes.io/rewrite-target: /` | `traefik.ingress.kubernetes.io/rewrite-target: /` |
| `nginx.ingress.kubernetes.io/ssl-redirect: "true"` | `traefik.ingress.kubernetes.io/router.middlewares: default-https-redirect@kubernetescrd` |
| `nginx.ingress.kubernetes.io/proxy-body-size: 50m` | `traefik.ingress.kubernetes.io/router.middlewares: default-body-size-limit@kubernetescrd` |
| `nginx.ingress.kubernetes.io/rate-limit: 100` | `traefik.ingress.kubernetes.io/router.middlewares: default-rate-limit@kubernetescrd` |
| `nginx.ingress.kubernetes.io/enable-cors: "true"` | `traefik.ingress.kubernetes.io/router.middlewares: default-secure-headers@kubernetescrd` |

### 4.2 Update Helm Values

Update API ingress configuration in `infrastructure/helm/api/values.yml`:

```yaml
ingress:
  enabled: true
  className: "traefik"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    traefik.ingress.kubernetes.io/router.middlewares: "default-default-headers@kubernetescrd,default-body-size-limit@kubernetescrd"
  hosts:
    - host: api.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: api-tls
      hosts:
        - api.example.com
```

Update production values in `infrastructure/helm/api/values-production.yml`:

```yaml
ingress:
  enabled: true
  className: "traefik"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    traefik.ingress.kubernetes.io/router.middlewares: "default-rate-limit@kubernetescrd,default-default-headers@kubernetescrd,default-body-size-limit@kubernetescrd"
  hosts:
    - host: api.yourcompany.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: api-prod-tls
      hosts:
        - api.yourcompany.com
```

Update frontend ingress configurations similarly.

### 4.3 Complex nginx Configurations

For complex nginx configurations, create custom Traefik middlewares:

**nginx rewrite example:**
```yaml
# nginx annotation
nginx.ingress.kubernetes.io/rewrite-target: /$2
nginx.ingress.kubernetes.io/use-regex: "true"
```

**Traefik equivalent:**
```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: api-rewrite
spec:
  replacePathRegex:
    regex: "^/api/(.*)"
    replacement: "/$1"
```

## Step 5: Update DNS and Load Balancer

### 5.1 Get Traefik Load Balancer IP

```bash
# Get Traefik service details
kubectl get service traefik -n traefik-system

# Get load balancer IP
TRAEFIK_LB_IP=$(kubectl get service traefik -n traefik-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Traefik Load Balancer IP: $TRAEFIK_LB_IP"
```

### 5.2 Update DNS Records

Update your DNS provider to point domains to the new Traefik load balancer IP:

```bash
# Example with Azure DNS (adjust for your provider)
az network dns record-set a delete -g $DNS_RESOURCE_GROUP -z $DOMAIN_NAME -n api --yes
az network dns record-set a create -g $DNS_RESOURCE_GROUP -z $DOMAIN_NAME -n api
az network dns record-set a add-record -g $DNS_RESOURCE_GROUP -z $DOMAIN_NAME -n api -a $TRAEFIK_LB_IP

# Repeat for other subdomains (app, grafana, etc.)
```

### 5.3 Test DNS Propagation

```bash
# Check DNS resolution
nslookup api.yourdomain.com
dig api.yourdomain.com A

# Test multiple subdomains
for subdomain in api app grafana; do
  echo "Testing $subdomain.yourdomain.com:"
  dig +short $subdomain.yourdomain.com A
done
```

## Step 6: Deploy Updated Applications

### 6.1 Deploy with Helm

```bash
# Deploy API with Traefik ingress
helm upgrade --install api ./infrastructure/helm/api \
  --namespace production \
  --values ./infrastructure/helm/api/values-production.yml

# Deploy Frontend with Traefik ingress
helm upgrade --install frontend ./infrastructure/helm/frontend \
  --namespace production \
  --values ./infrastructure/helm/frontend/values-production.yml
```

### 6.2 Verify Ingress Resources

```bash
# Check ingress resources
kubectl get ingress -A

# Verify Traefik is managing ingresses
kubectl describe ingress api-ingress -n production

# Check Traefik routes
kubectl get ingressroute -A
```

## Step 7: Configure SSL/TLS Certificates

### 7.1 Verify cert-manager Integration

```bash
# Check certificate status
kubectl get certificates -A

# Check certificate requests
kubectl get certificaterequests -A

# Describe certificate issues if any
kubectl describe certificate api-tls -n production
```

### 7.2 Force Certificate Renewal (if needed)

```bash
# Delete existing certificates to trigger renewal
kubectl delete certificate api-tls -n production
kubectl delete certificate frontend-tls -n production

# Monitor certificate recreation
kubectl get certificates -A -w
```

### 7.3 Test HTTPS Endpoints

```bash
# Test API endpoint
curl -k https://api.yourdomain.com/health

# Test with certificate verification
curl https://api.yourdomain.com/health

# Check certificate details
openssl s_client -connect api.yourdomain.com:443 -servername api.yourdomain.com
```

## Step 8: Performance and Feature Testing

### 8.1 Test Traefik Middlewares

```bash
# Test rate limiting
for i in {1..150}; do curl https://api.yourdomain.com/health; done

# Test body size limits
curl -X POST https://api.yourdomain.com/upload \
  --data-binary @large-file.txt \
  -H "Content-Type: application/octet-stream"

# Test CORS headers
curl -H "Origin: https://example.com" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: X-Requested-With" \
  -X OPTIONS https://api.yourdomain.com/api/test
```

### 8.2 Monitor Traefik Dashboard

```bash
# Access Traefik dashboard
kubectl port-forward -n traefik-system svc/traefik 8080:8080

# Or create an ingress for the dashboard
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: traefik-dashboard
  namespace: traefik-system
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: "traefik-system-auth@kubernetescrd"
spec:
  ingressClassName: traefik
  rules:
  - host: traefik.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api@internal
            port:
              number: 8080
EOF
```

### 8.3 Performance Comparison

```bash
# Test response times
curl -w "@curl-format.txt" -s -o /dev/null https://api.yourdomain.com/health

# Create curl-format.txt:
cat > curl-format.txt << EOF
     time_namelookup:  %{time_namelookup}\n
        time_connect:  %{time_connect}\n
     time_appconnect:  %{time_appconnect}\n
    time_pretransfer:  %{time_pretransfer}\n
       time_redirect:  %{time_redirect}\n
  time_starttransfer:  %{time_starttransfer}\n
                     ----------\n
          time_total:  %{time_total}\n
EOF
```

## Step 9: Remove nginx Ingress Controller

### 9.1 Verify Traefik is Working

Before removing nginx, ensure all services are working with Traefik:

```bash
# Test all endpoints
endpoints=("api.yourdomain.com" "app.yourdomain.com" "grafana.yourdomain.com")

for endpoint in "${endpoints[@]}"; do
  echo "Testing https://$endpoint"
  curl -I https://$endpoint
  echo "---"
done
```

### 9.2 Remove nginx Ingress Controller

```bash
# If installed via Helm
helm uninstall ingress-nginx -n ingress-nginx

# Delete namespace
kubectl delete namespace ingress-nginx

# If installed via Terraform, remove from configuration
# Comment out or remove nginx ingress resources from main.tf
```

### 9.3 Clean Up nginx Resources

```bash
# Remove any remaining nginx resources
kubectl delete clusterrole ingress-nginx
kubectl delete clusterrolebinding ingress-nginx
kubectl delete serviceaccount ingress-nginx -n ingress-nginx

# Clean up any nginx-specific configmaps
kubectl delete configmap nginx-configuration -n ingress-nginx
kubectl delete configmap tcp-services -n ingress-nginx
kubectl delete configmap udp-services -n ingress-nginx
```

## Step 10: Monitoring and Observability

### 10.1 Set up Traefik Metrics

Update Traefik configuration to enable metrics:

```yaml
# Add to Traefik Helm values or Terraform
metrics:
  prometheus:
    enabled: true
    addEntryPointsLabels: true
    addServicesLabels: true
  datadog:
    enabled: false
  statsd:
    enabled: false
```

### 10.2 Configure Prometheus Monitoring

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: traefik-prometheus-config
data:
  prometheus.yml: |
    global:
      scrape_interval: 30s
    scrape_configs:
    - job_name: 'traefik'
      static_configs:
      - targets: ['traefik.traefik-system:8080']
```

### 10.3 Grafana Dashboard

Import Traefik dashboard in Grafana:

```bash
# Dashboard ID: 4475 (Traefik 2.0)
# Or use the official Traefik dashboard JSON
```

## Troubleshooting

### Common Issues

1. **Certificate Issues**
   ```bash
   # Check cert-manager logs
   kubectl logs -n cert-manager deployment/cert-manager
   
   # Force certificate regeneration
   kubectl delete certificaterequest --all -n production
   ```

2. **Middleware Not Working**
   ```bash
   # Check middleware status
   kubectl get middlewares -A
   
   # Verify middleware reference in ingress
   kubectl describe ingress api-ingress -n production
   ```

3. **Service Discovery Issues**
   ```bash
   # Check Traefik logs
   kubectl logs -n traefik-system deployment/traefik
   
   # Verify service endpoints
   kubectl get endpoints -A
   ```

4. **DNS Resolution Problems**
   ```bash
   # Check CoreDNS
   kubectl get pods -n kube-system | grep coredns
   
   # Test internal DNS
   kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default
   ```

### Useful Debug Commands

```bash
# Check all ingress resources
kubectl get ingress,ingressroute,middleware -A

# View Traefik configuration
kubectl exec -n traefik-system deployment/traefik -- traefik dump

# Check service connectivity
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- bash

# Monitor ingress events
kubectl get events --field-selector involvedObject.kind=Ingress -A --watch
```

## Migration Checklist

- [ ] Audit existing nginx ingress configurations
- [ ] Install Traefik ingress controller
- [ ] Create necessary Traefik middlewares
- [ ] Convert nginx annotations to Traefik format
- [ ] Update DNS records to point to Traefik load balancer
- [ ] Deploy applications with updated ingress configurations
- [ ] Verify SSL/TLS certificates are working
- [ ] Test all application endpoints
- [ ] Validate middleware functionality (rate limiting, CORS, etc.)
- [ ] Monitor Traefik dashboard and metrics
- [ ] Remove nginx ingress controller
- [ ] Update documentation and runbooks
- [ ] Configure monitoring and alerting
- [ ] Perform load testing
- [ ] Train team on Traefik-specific debugging

## Rollback Plan

If issues arise during migration:

1. **Immediate Rollback**
   ```bash
   # Update DNS back to nginx load balancer IP
   # Reinstall nginx ingress controller
   helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace
   
   # Revert ingress configurations
   kubectl apply -f nginx-ingress-backup.yaml
   ```

2. **Gradual Rollback**
   - Change ingress class back to nginx for specific services
   - Keep both controllers running during transition
   - Route different services through different controllers

3. **Post-Rollback Cleanup**
   ```bash
   # Remove Traefik if rollback is permanent
   helm uninstall traefik -n traefik-system
   kubectl delete namespace traefik-system
   ```

## Best Practices

1. **Middleware Management**
   - Create reusable middlewares for common functionality
   - Use namespace-specific middlewares for isolation
   - Version control middleware configurations

2. **Security**
   - Always use HTTPS redirects
   - Implement proper CORS policies
   - Set up authentication middlewares where needed
   - Regular security headers implementation

3. **Performance**
   - Use compression middleware for text content
   - Implement appropriate rate limiting
   - Monitor response times and adjust accordingly

4. **Monitoring**
   - Set up comprehensive dashboards
   - Configure alerts for high error rates
   - Monitor certificate expiration dates

5. **Documentation**
   - Keep ingress configurations well-documented
   - Maintain middleware inventory
   - Document troubleshooting procedures

This completes the migration from nginx ingress to Traefik ingress. Monitor the system closely after migration and adjust configurations as needed for optimal performance.