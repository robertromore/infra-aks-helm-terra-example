# Migrating from Traefik Ingress to nginx Ingress

This document provides comprehensive step-by-step instructions for migrating from Traefik ingress controller to nginx ingress controller on Azure Kubernetes Service (AKS). This migration might be necessary for standardization, compatibility requirements, or organizational preferences.

## Overview

This migration involves:
- Removing Traefik ingress controller resources
- Installing nginx ingress controller
- Converting Traefik middlewares to nginx annotations
- Updating ingress resources and configurations
- Migrating SSL/TLS certificate configurations
- Testing and validating the new setup

## Why Migrate to nginx Ingress?

### Benefits
- **Industry Standard**: Most widely adopted ingress controller
- **Mature Ecosystem**: Extensive documentation and community support
- **Enterprise Features**: Advanced load balancing and SSL termination
- **Flexibility**: Highly configurable with extensive annotation support
- **Stability**: Proven in production environments worldwide
- **Compatibility**: Better compatibility with legacy applications

### Feature Comparison
| Feature | Traefik | nginx Ingress |
|---------|---------|---------------|
| Adoption | Growing | Dominant |
| Configuration | Middlewares | Annotations |
| Dashboard | Advanced | Basic |
| Performance | Excellent | Very Good |
| Flexibility | High | Very High |
| Learning Curve | Moderate | Low |

## Prerequisites

- Existing AKS cluster with Traefik ingress controller
- kubectl configured and accessible
- Helm 3.x installed
- Terraform configured (if using IaC)
- Administrative access to DNS provider
- Backup of current Traefik configurations

## Step 1: Audit Current Traefik Configuration

### 1.1 Document Existing Ingresses

```bash
# List all ingresses
kubectl get ingress --all-namespaces -o wide

# Export ingress configurations
kubectl get ingress --all-namespaces -o yaml > traefik-ingress-backup.yaml

# Document Traefik-specific annotations
grep -r "traefik.ingress.kubernetes.io" . --include="*.yaml" --include="*.yml"

# List Traefik middlewares
kubectl get middlewares --all-namespaces -o yaml > traefik-middlewares-backup.yaml

# List Traefik IngressRoutes
kubectl get ingressroute --all-namespaces -o yaml > traefik-ingressroutes-backup.yaml
```

### 1.2 Identify Traefik-Specific Features

Common Traefik features to convert:
- Middlewares (rate limiting, headers, authentication)
- `traefik.ingress.kubernetes.io/router.middlewares`
- `traefik.ingress.kubernetes.io/rewrite-target`
- IngressRoute resources
- Custom Traefik configurations

### 1.3 Check Traefik Controller Status

```bash
# Check Traefik controller pods
kubectl get pods -n traefik-system

# Check Traefik controller service
kubectl get service -n traefik-system

# Get load balancer IP
kubectl get service traefik -n traefik-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Check Traefik middlewares
kubectl get middlewares --all-namespaces
```

## Step 2: Install nginx Ingress Controller

### 2.1 Terraform Configuration

Update `infrastructure/terraform/main.tf`:

```hcl
# nginx Ingress Controller
resource "helm_release" "nginx_ingress" {
  name       = "nginx-ingress"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = "ingress-nginx"
  version    = "4.8.3"
  
  create_namespace = true
  
  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }
  
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-health-probe-request-path"
    value = "/healthz"
  }

  # Enable metrics
  set {
    name  = "controller.metrics.enabled"
    value = "true"
  }

  set {
    name  = "controller.podAnnotations.prometheus\\.io/scrape"
    value = "true"
  }

  set {
    name  = "controller.podAnnotations.prometheus\\.io/port"
    value = "10254"
  }

  # Configure default backend
  set {
    name  = "defaultBackend.enabled"
    value = "true"
  }

  # Enable admission webhooks
  set {
    name  = "controller.admissionWebhooks.enabled"
    value = "true"
  }

  depends_on = [azurerm_kubernetes_cluster.main]
}
```

### 2.2 Manual Installation with Helm

```bash
# Add nginx ingress Helm repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install nginx ingress
helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"="/healthz" \
  --set controller.metrics.enabled=true \
  --set defaultBackend.enabled=true
```

### 2.3 Verify nginx Installation

```bash
# Check nginx pods
kubectl get pods -n ingress-nginx

# Check nginx service
kubectl get service -n ingress-nginx

# Verify nginx controller is ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

## Step 3: Convert Traefik Middlewares to nginx Annotations

### 3.1 Middleware to Annotation Mapping

| Traefik Middleware | nginx Annotation |
|-------------------|------------------|
| headers (security headers) | `nginx.ingress.kubernetes.io/configuration-snippet` |
| rateLimit | `nginx.ingress.kubernetes.io/rate-limit`, `nginx.ingress.kubernetes.io/rate-limit-window` |
| stripPrefix | `nginx.ingress.kubernetes.io/rewrite-target` |
| redirectScheme (HTTPS) | `nginx.ingress.kubernetes.io/ssl-redirect` |
| compress | `nginx.ingress.kubernetes.io/enable-brotli`, `nginx.ingress.kubernetes.io/enable-gzip` |
| buffering | `nginx.ingress.kubernetes.io/proxy-body-size` |

### 3.2 Create nginx Configuration Templates

Create `infrastructure/nginx-configs/` directory with configuration snippets:

**security-headers.conf:**
```nginx
more_set_headers "X-Content-Type-Options: nosniff";
more_set_headers "X-Frame-Options: DENY";
more_set_headers "X-XSS-Protection: 1; mode=block";
more_set_headers "Referrer-Policy: strict-origin-when-cross-origin";
```

**cors-headers.conf:**
```nginx
more_set_headers "Access-Control-Allow-Origin: *";
more_set_headers "Access-Control-Allow-Methods: GET, POST, PUT, DELETE, PATCH, OPTIONS";
more_set_headers "Access-Control-Allow-Headers: DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization";
more_set_headers "Access-Control-Expose-Headers: Content-Length,Content-Range";
```

### 3.3 Create nginx ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-configuration
  namespace: ingress-nginx
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
data:
  # Global configurations
  enable-brotli: "true"
  enable-gzip: "true"
  gzip-level: "6"
  use-gzip: "true"
  
  # Security settings
  ssl-protocols: "TLSv1.2 TLSv1.3"
  ssl-ciphers: "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384"
  ssl-prefer-server-ciphers: "false"
  
  # Rate limiting defaults
  limit-connections: "10"
  limit-rps: "100"
  
  # Proxy settings
  proxy-body-size: "50m"
  proxy-connect-timeout: "5"
  proxy-send-timeout: "60"
  proxy-read-timeout: "60"
  
  # Custom error pages
  custom-http-errors: "404,503"
```

Apply the ConfigMap:
```bash
kubectl apply -f nginx-configuration.yaml
```

## Step 4: Convert Ingress Resources

### 4.1 Update Helm Values Files

Update API ingress configuration in `infrastructure/helm/api/values.yml`:

```yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "10m"
    nginx.ingress.kubernetes.io/rate-limit: "100"
    nginx.ingress.kubernetes.io/rate-limit-window: "1m"
    nginx.ingress.kubernetes.io/configuration-snippet: |
      more_set_headers "X-Content-Type-Options: nosniff";
      more_set_headers "X-Frame-Options: DENY";
      more_set_headers "X-XSS-Protection: 1; mode=block";
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
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/rate-limit: "100"
    nginx.ingress.kubernetes.io/rate-limit-window: "1m"
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-origin: "*"
    nginx.ingress.kubernetes.io/cors-allow-methods: "GET, POST, PUT, DELETE, PATCH, OPTIONS"
    nginx.ingress.kubernetes.io/cors-allow-headers: "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization"
    nginx.ingress.kubernetes.io/configuration-snippet: |
      more_set_headers "X-Content-Type-Options: nosniff";
      more_set_headers "X-Frame-Options: DENY";
      more_set_headers "X-XSS-Protection: 1; mode=block";
      more_set_headers "Referrer-Policy: strict-origin-when-cross-origin";
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

### 4.2 Convert Complex Traefik Configurations

**Traefik IngressRoute to nginx Ingress:**

Traefik IngressRoute:
```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: api-secure
spec:
  entryPoints:
    - websecure
  routes:
  - match: Host(`api.example.com`) && PathPrefix(`/v1/`)
    kind: Rule
    services:
    - name: api-service
      port: 8080
    middlewares:
    - name: strip-prefix
    - name: rate-limit
  tls:
    secretName: api-tls
```

nginx Ingress equivalent:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/rate-limit: "100"
    nginx.ingress.kubernetes.io/rate-limit-window: "1m"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - api.example.com
    secretName: api-tls
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /v1/(.*)
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 8080
```

### 4.3 Handle Authentication Middlewares

Convert Traefik authentication to nginx:

**Traefik BasicAuth Middleware:**
```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: basic-auth
spec:
  basicAuth:
    secret: auth-secret
```

**nginx equivalent:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: protected-ingress
  annotations:
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: auth-secret
    nginx.ingress.kubernetes.io/auth-realm: 'Authentication Required'
```

## Step 5: Update DNS and Load Balancer

### 5.1 Get nginx Load Balancer IP

```bash
# Get nginx service details
kubectl get service ingress-nginx-controller -n ingress-nginx

# Get load balancer IP
NGINX_LB_IP=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "nginx Load Balancer IP: $NGINX_LB_IP"
```

### 5.2 Update DNS Records

Update DNS to point to nginx load balancer:

```bash
# Example with Azure DNS
az network dns record-set a delete -g $DNS_RESOURCE_GROUP -z $DOMAIN_NAME -n api --yes
az network dns record-set a create -g $DNS_RESOURCE_GROUP -z $DOMAIN_NAME -n api
az network dns record-set a add-record -g $DNS_RESOURCE_GROUP -z $DOMAIN_NAME -n api -a $NGINX_LB_IP

# Update other subdomains
for subdomain in app grafana; do
  az network dns record-set a delete -g $DNS_RESOURCE_GROUP -z $DOMAIN_NAME -n $subdomain --yes
  az network dns record-set a create -g $DNS_RESOURCE_GROUP -z $DOMAIN_NAME -n $subdomain
  az network dns record-set a add-record -g $DNS_RESOURCE_GROUP -z $DOMAIN_NAME -n $subdomain -a $NGINX_LB_IP
done
```

### 5.3 Verify DNS Propagation

```bash
# Test DNS resolution
for subdomain in api app grafana; do
  echo "Testing $subdomain.yourdomain.com:"
  dig +short $subdomain.yourdomain.com A
  echo "Expected: $NGINX_LB_IP"
  echo "---"
done

# Wait for propagation
sleep 300
```

## Step 6: Deploy Updated Applications

### 6.1 Deploy with Helm

```bash
# Deploy API with nginx ingress
helm upgrade --install api ./infrastructure/helm/api \
  --namespace production \
  --values ./infrastructure/helm/api/values-production.yml

# Deploy Frontend with nginx ingress
helm upgrade --install frontend ./infrastructure/helm/frontend \
  --namespace production \
  --values ./infrastructure/helm/frontend/values-production.yml
```

### 6.2 Verify Ingress Resources

```bash
# Check ingress resources
kubectl get ingress -A

# Verify nginx is managing ingresses
kubectl describe ingress api-ingress -n production

# Check nginx controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller
```

## Step 7: Configure SSL/TLS Certificates

### 7.1 Verify cert-manager Integration

```bash
# Check certificate status
kubectl get certificates -A

# Check nginx integration with cert-manager
kubectl describe ingress api-ingress -n production | grep -A 5 -B 5 cert-manager

# Monitor certificate requests
kubectl get certificaterequests -A -w
```

### 7.2 Force Certificate Renewal

```bash
# Delete certificates to trigger renewal with nginx
kubectl delete certificate api-tls -n production
kubectl delete certificate frontend-tls -n production

# Monitor recreation
kubectl get certificates -A -w

# Check nginx SSL configuration
kubectl exec -n ingress-nginx deployment/ingress-nginx-controller -- nginx -T | grep ssl
```

### 7.3 Test HTTPS Endpoints

```bash
# Test API endpoint
curl -I https://api.yourdomain.com/health

# Verify certificate
echo | openssl s_client -connect api.yourdomain.com:443 -servername api.yourdomain.com 2>/dev/null | openssl x509 -noout -issuer -subject -dates

# Test redirect from HTTP to HTTPS
curl -I http://api.yourdomain.com/health
```

## Step 8: Configure nginx-Specific Features

### 8.1 Set Up Custom Error Pages

Create custom error pages:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-error-pages
  namespace: ingress-nginx
data:
  404.html: |
    <!DOCTYPE html>
    <html>
    <head>
        <title>404 - Page Not Found</title>
        <style>
            body { font-family: Arial, sans-serif; text-align: center; margin-top: 50px; }
            .error-code { font-size: 72px; color: #333; }
            .error-message { font-size: 24px; color: #666; }
        </style>
    </head>
    <body>
        <div class="error-code">404</div>
        <div class="error-message">The page you're looking for doesn't exist.</div>
    </body>
    </html>

  503.html: |
    <!DOCTYPE html>
    <html>
    <head>
        <title>503 - Service Temporarily Unavailable</title>
        <style>
            body { font-family: Arial, sans-serif; text-align: center; margin-top: 50px; }
            .error-code { font-size: 72px; color: #333; }
            .error-message { font-size: 24px; color: #666; }
        </style>
    </head>
    <body>
        <div class="error-code">503</div>
        <div class="error-message">Service temporarily unavailable. Please try again later.</div>
    </body>
    </html>
```

### 8.2 Configure Rate Limiting

Apply advanced rate limiting:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-with-advanced-rate-limit
  annotations:
    nginx.ingress.kubernetes.io/rate-limit: "100"
    nginx.ingress.kubernetes.io/rate-limit-window: "1m"
    nginx.ingress.kubernetes.io/rate-limit-connections: "10"
    nginx.ingress.kubernetes.io/configuration-snippet: |
      limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
      limit_req zone=api burst=20 nodelay;
```

### 8.3 Enable Monitoring and Observability

Update nginx controller for better monitoring:

```bash
# Enable nginx Prometheus metrics
helm upgrade nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.metrics.enabled=true \
  --set controller.metrics.serviceMonitor.enabled=true \
  --set controller.podAnnotations."prometheus\.io/scrape"="true" \
  --set controller.podAnnotations."prometheus\.io/port"="10254"
```

## Step 9: Performance Testing and Optimization

### 9.1 Test nginx Performance

```bash
# Test response times
curl -w "@curl-format.txt" -s -o /dev/null https://api.yourdomain.com/health

# Load testing with Apache Bench
ab -n 1000 -c 10 https://api.yourdomain.com/health

# Test rate limiting
for i in {1..150}; do 
  curl -s -o /dev/null -w "Request $i: %{http_code} - %{time_total}s\n" https://api.yourdomain.com/health
done
```

### 9.2 Optimize nginx Configuration

```yaml
# Add to nginx ConfigMap for performance
data:
  # Worker processes
  worker-processes: "auto"
  worker-connections: "1024"
  
  # Keepalive
  keep-alive: "75"
  keep-alive-requests: "1000"
  
  # Buffers
  client-body-buffer-size: "16k"
  client-header-buffer-size: "1k"
  large-client-header-buffers: "4 8k"
  
  # Timeouts
  client-body-timeout: "60"
  client-header-timeout: "60"
  send-timeout: "60"
  
  # Gzip optimization
  gzip-level: "6"
  gzip-min-length: "1024"
  gzip-types: "text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript application/octet-stream"
```

### 9.3 Configure Health Checks

```bash
# Check nginx controller health
kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller

# Test health endpoint
curl http://$NGINX_LB_IP/healthz

# Monitor nginx metrics
curl http://$NGINX_LB_IP:10254/metrics
```

## Step 10: Remove Traefik Ingress Controller

### 10.1 Verify nginx is Working

Test all services are working with nginx:

```bash
# Test all endpoints
endpoints=("api.yourdomain.com" "app.yourdomain.com" "grafana.yourdomain.com")

for endpoint in "${endpoints[@]}"; do
  echo "Testing https://$endpoint"
  response=$(curl -s -o /dev/null -w "%{http_code}" https://$endpoint)
  if [ $response -eq 200 ] || [ $response -eq 301 ] || [ $response -eq 302 ]; then
    echo "✓ $endpoint is working (HTTP $response)"
  else
    echo "✗ $endpoint failed (HTTP $response)"
  fi
  echo "---"
done
```

### 10.2 Remove Traefik Resources

```bash
# Remove Traefik Helm release
helm uninstall traefik -n traefik-system

# Delete Traefik namespace
kubectl delete namespace traefik-system

# Remove Traefik CRDs
kubectl delete crd \
  ingressroutes.traefik.containo.us \
  ingressroutetcps.traefik.containo.us \
  ingressrouteudps.traefik.containo.us \
  middlewares.traefik.containo.us \
  middlewaretcps.traefik.containo.us \
  serverstransports.traefik.containo.us \
  tlsoptions.traefik.containo.us \
  tlsstores.traefik.containo.us \
  traefikservices.traefik.containo.us
```

### 10.3 Clean Up Traefik Configurations

```bash
# Remove Traefik-specific resources
kubectl delete middlewares --all --all-namespaces
kubectl delete ingressroute --all --all-namespaces

# Remove Traefik ConfigMaps
kubectl delete configmap traefik-config -n traefik-system || true

# Clean up any remaining Traefik resources
kubectl get all --all-namespaces | grep traefik
```

## Step 11: Advanced nginx Configurations

### 11.1 Configure Load Balancing Algorithms

```yaml
# Add to ingress annotations for specific load balancing
annotations:
  nginx.ingress.kubernetes.io/upstream-hash-by: "$request_uri"  # Consistent hashing
  nginx.ingress.kubernetes.io/load-balance: "ewma"  # Weighted moving average
  nginx.ingress.kubernetes.io/upstream-max-fails: "3"
  nginx.ingress.kubernetes.io/upstream-fail-timeout: "30s"
```

### 11.2 Set Up Session Affinity

```yaml
# Configure session stickiness
annotations:
  nginx.ingress.kubernetes.io/affinity: "cookie"
  nginx.ingress.kubernetes.io/affinity-mode: "persistent"
  nginx.ingress.kubernetes.io/session-cookie-name: "route"
  nginx.ingress.kubernetes.io/session-cookie-max-age: "3600"
```

### 11.3 Configure Advanced Security

```yaml
# Enhanced security annotations
annotations:
  nginx.ingress.kubernetes.io/server-snippet: |
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
      expires 1y;
      add_header Cache-Control "public, immutable";
    }
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Hide nginx version
    server_tokens off;
  
  # WAF-like protection
  nginx.ingress.kubernetes.io/enable-modsecurity: "true"
  nginx.ingress.kubernetes.io/modsecurity-snippet: |
    SecRuleEngine On
    SecRequestBodyAccess On
    SecRule REQUEST_HEADERS:Content-Type "text/xml" \
      "id:'200001',phase:1,t:none,t:lowercase,pass,nolog,ctl:requestBodyProcessor=XML"
```

## Troubleshooting

### Common Issues

1. **Certificate Issues with nginx**
   ```bash
   # Check cert-manager nginx class support
   kubectl get clusterissuer -o yaml | grep nginx
   
   # Force certificate regeneration
   kubectl annotate certificate api-tls -n production cert-manager.io/issue-temporary-certificate=true
   
   # Check nginx SSL configuration
   kubectl exec -n ingress-nginx deployment/ingress-nginx-controller -- nginx -T | grep -A 20 "ssl_certificate"
   ```

2. **nginx Configuration Errors**
   ```bash
   # Check nginx configuration syntax
   kubectl exec -n ingress-nginx deployment/ingress-nginx-controller -- nginx -t
   
   # View nginx configuration
   kubectl exec -n ingress-nginx deployment/ingress-nginx-controller -- nginx -T
   
   # Check nginx error logs
   kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=100
   ```

3. **Ingress Not Working**
   ```bash
   # Check ingress class
   kubectl get ingressclass
   
   # Verify ingress events
   kubectl describe ingress api-ingress -n production
   
   # Check service endpoints
   kubectl get endpoints api-service -n production
   ```

4. **Rate Limiting Issues**
   ```bash
   # Check rate limiting configuration
   kubectl get configmap nginx-configuration -n ingress-nginx -o yaml
   
   # Test rate limits
   for i in {1..20}; do curl -I https://api.yourdomain.com/health; sleep 0.1; done
   ```

### Debug Commands

```bash
# Check all nginx-related resources
kubectl get all -n ingress-nginx

# Verify nginx controller configuration
kubectl describe configmap nginx-configuration -n ingress-nginx

# Check ingress controller events
kubectl get events -n ingress-nginx --sort-by=.metadata.creationTimestamp

# Monitor nginx access logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller -f

# Test nginx connectivity
kubectl run test-pod --image=nginx --rm -it --restart=Never -- curl -I http://ingress-nginx-controller.ingress-nginx.svc.cluster.local
```

## Migration Checklist

- [ ] Audit existing Traefik configurations and middlewares
- [ ] Install nginx ingress controller
- [ ] Convert Traefik middlewares to nginx annotations
- [ ] Update ingress resources to use nginx class
- [ ] Configure nginx-specific features and optimizations
- [ ] Update DNS records to point to nginx load balancer
- [ ] Deploy applications with updated ingress configurations
- [ ] Verify SSL/TLS certificates are working with nginx
- [ ] Test all application endpoints and functionality
- [ ] Validate rate limiting, CORS, and other policies
- [ ] Configure monitoring and logging
- [ ] Remove Traefik ingress controller and resources
- [ ] Update documentation and runbooks
- [ ] Train team on nginx-specific troubleshooting
- [ ] Perform comprehensive load testing

## Rollback Plan

If issues arise during migration:

1. **Immediate Rollback**
   ```bash
   # Reinstall Traefik
   helm install traefik traefik/traefik -n traefik-system --create-namespace
   
   # Update DNS back to Traefik load balancer
   # Revert ingress configurations
   kubectl apply -f traefik-ingress-backup.yaml
   kubectl apply -f traefik-middlewares-backup.yaml
   ```

2. **Gradual Rollback**
   - Change ingress class back to traefik for specific services
   - Keep both controllers running during transition
   - Route different services through different controllers

3. **Post-Rollback Cleanup**
   ```bash
   # Remove nginx if rollback is permanent
   helm uninstall nginx-ingress -n ingress-nginx
   kubectl delete namespace ingress-nginx
   ```

## Performance Comparison

### Metrics to Monitor

1. **Response Times**
   ```bash
   # Before and after comparison
   curl -w "@curl-format.txt" -s -o /dev/null https://api.yourdomain.com/health
   ```

2. **Throughput Testing**
   ```bash
   # Load testing
   ab -n 10000 -c 100 https://api.yourdomain.com/health
   ```

3. **Resource Usage**
   ```bash
   # Monitor controller resource usage
   kubectl top pods -n ingress-nginx
   kubectl top pods -n traefik-system  # For comparison
   ```

## Best Practices

1. **Configuration Management**
   - Use ConfigMaps for global nginx settings
   - Implement proper annotation standards
   - Version control all configurations
   - Use staging environments for testing

2. **Security**
   - Implement proper rate limiting
   - Use security headers consistently
   - Enable ModSecurity where appropriate
   - Regular security audits of configurations

3. **Performance**
   - Optimize nginx worker settings
   - Enable appropriate compression
   - Configure proper caching headers
   - Monitor and tune timeouts

4. **Monitoring**
   - Set up comprehensive dashboards
   - Configure alerts for high error rates
   - Monitor SSL certificate expiration
   - Track performance metrics

5. **Maintenance**
   - Regular nginx controller updates
   - Periodic configuration reviews
   
