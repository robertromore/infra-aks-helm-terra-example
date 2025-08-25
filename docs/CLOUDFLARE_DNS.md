# Cloudflare DNS Validation Guide

This document provides comprehensive instructions for setting up Cloudflare DNS validation with cert-manager for automated SSL/TLS certificate management in your AKS cluster.

## Overview

Cloudflare DNS validation allows cert-manager to automatically obtain and renew SSL/TLS certificates from Let's Encrypt using the DNS-01 challenge method. This approach is particularly useful for:

- **Wildcard certificates**: Obtain certificates for `*.yourdomain.com`
- **Private networks**: Validate domains that are not publicly accessible
- **Rate limit avoidance**: DNS challenges have higher rate limits than HTTP challenges
- **Automated renewal**: Certificates renew automatically without downtime

## Prerequisites

- Cloudflare account with your domain configured
- Cloudflare API Token with appropriate permissions
- AKS cluster with cert-manager installed
- Terraform configured for infrastructure management

## Cloudflare Setup

### 1. Create Cloudflare API Token

1. **Log into Cloudflare Dashboard**:
   - Go to [Cloudflare Dashboard](https://dash.cloudflare.com/)
   - Navigate to "My Profile" → "API Tokens"

2. **Create Custom Token**:
   ```
   Token name: cert-manager-dns01
   Permissions:
   - Zone:Zone:Read
   - Zone:DNS:Edit
   Resources:
   - Include:Zone:yourdomain.com
   ```

3. **Copy the generated token** (you'll only see it once)

### 2. Get Zone ID

1. In Cloudflare Dashboard, select your domain
2. In the right sidebar, copy the "Zone ID"

### 3. Verify API Access

Test your API token:
```bash
curl -X GET "https://api.cloudflare.com/client/v4/zones" \
  -H "Authorization: Bearer YOUR_API_TOKEN" \
  -H "Content-Type: application/json"
```

## Terraform Configuration

### 1. Set Required Variables

Create or update your `terraform.tfvars` file:

```hcl
# Domain configuration
domain_name = "yourdomain.com"

# Cloudflare credentials
cloudflare_api_token = "your-cloudflare-api-token"
cloudflare_zone_id   = "your-cloudflare-zone-id"

# GitHub Container Registry
github_username = "your-github-username"
github_token    = "your-github-pat"
github_email    = "your-email@yourdomain.com"
```

### 2. Environment Variables (Alternative)

For enhanced security, use environment variables:

```bash
export TF_VAR_cloudflare_api_token="your-cloudflare-api-token"
export TF_VAR_cloudflare_zone_id="your-cloudflare-zone-id"
export TF_VAR_domain_name="yourdomain.com"
```

### 3. Deploy Infrastructure

```bash
cd infrastructure/terraform

# Initialize and plan
terraform init
terraform plan -var-file="environments/production.tfvars"

# Apply changes
terraform apply -var-file="environments/production.tfvars"
```

## Components Created

### 1. Kubernetes Secret
- **Name**: `cloudflare-api-token-secret`
- **Namespace**: `cert-manager`
- **Content**: Cloudflare API token for DNS challenges

### 2. ClusterIssuers
- **letsencrypt-staging**: For testing (staging certificates)
- **letsencrypt-prod**: For production (trusted certificates)

### 3. Wildcard Certificates
Automatically created in multiple namespaces:
- `default`
- `production`
- `staging`

## Certificate Configuration

### Automatic Certificate Management

Your ingresses will automatically request certificates when configured with:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
    - hosts:
        - api.yourdomain.com
      secretName: wildcard-yourdomain-com-tls
```

### Using Wildcard Certificates

The Terraform configuration creates wildcard certificates that can be used by multiple services:

```yaml
# API Ingress
spec:
  tls:
    - hosts:
        - api.yourdomain.com
      secretName: wildcard-yourdomain-com-tls

# Frontend Ingress  
spec:
  tls:
    - hosts:
        - app.yourdomain.com
      secretName: wildcard-yourdomain-com-tls
```

## Domain Configuration

### 1. Update Helm Values

Update your Helm values files to use your actual domain:

**API Production** (`infrastructure/helm/api/values-production.yml`):
```yaml
ingress:
  hosts:
    - host: api.yourdomain.com
  tls:
    - secretName: wildcard-yourdomain-com-tls
      hosts:
        - api.yourdomain.com
```

**Frontend Production** (`infrastructure/helm/frontend/values-production.yml`):
```yaml
ingress:
  hosts:
    - host: app.yourdomain.com
  tls:
    - secretName: wildcard-yourdomain-com-tls
      hosts:
        - app.yourdomain.com
```

### 2. Create DNS Records

In Cloudflare, create A records pointing to your AKS load balancer:

```bash
# Get load balancer IP
kubectl get service -n traefik-system traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Create these DNS records in Cloudflare:
- `api.yourdomain.com` → `YOUR_LOAD_BALANCER_IP`
- `app.yourdomain.com` → `YOUR_LOAD_BALANCER_IP`
- `grafana.yourdomain.com` → `YOUR_LOAD_BALANCER_IP`

## Validation and Troubleshooting

### 1. Check ClusterIssuers

```bash
kubectl get clusterissuers
kubectl describe clusterissuer letsencrypt-prod
```

Expected status: `Ready: True`

### 2. Check Certificates

```bash
# List certificates
kubectl get certificates -A

# Check certificate details
kubectl describe certificate wildcard-yourdomain-com -n production
```

### 3. Check Certificate Requests

```bash
# List certificate requests
kubectl get certificaterequests -A

# Check request details
kubectl describe certificaterequests -n production
```

### 4. View cert-manager Logs

```bash
kubectl logs -n cert-manager deployment/cert-manager -f
```

### 5. Test DNS Challenge

Manually test DNS challenge:
```bash
# Check if DNS TXT record is created during challenge
dig TXT _acme-challenge.yourdomain.com @8.8.8.8
```

## Common Issues and Solutions

### 1. Invalid API Token

**Error**: `401 Unauthorized`

**Solution**:
- Verify API token has correct permissions
- Check token hasn't expired
- Ensure Zone ID is correct

### 2. DNS Propagation Issues

**Error**: `DNS problem: NXDOMAIN looking up TXT for _acme-challenge.yourdomain.com`

**Solution**:
- Wait for DNS propagation (up to 5 minutes)
- Check Cloudflare DNS settings
- Verify domain is properly configured in Cloudflare

### 3. Rate Limiting

**Error**: `too many certificates already issued`

**Solution**:
- Use staging issuer first for testing
- Check Let's Encrypt rate limits
- Wait for rate limit reset (weekly)

### 4. Certificate Not Ready

**Error**: Certificate shows `Ready: False`

**Solution**:
```bash
# Check certificate events
kubectl describe certificate wildcard-yourdomain-com -n production

# Check certificate request
kubectl get certificaterequests -n production

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager --tail=100
```

## Security Best Practices

### 1. API Token Security

- **Principle of Least Privilege**: Only grant necessary permissions
- **Token Rotation**: Regularly rotate API tokens
- **Environment Variables**: Use environment variables, not hardcoded values
- **Secret Management**: Consider using Azure Key Vault for token storage

### 2. Certificate Management

- **Staging First**: Always test with staging issuer first
- **Monitoring**: Set up alerts for certificate expiration
- **Backup**: Store certificate backup in secure location
- **Access Control**: Limit access to certificate secrets

## Monitoring and Alerts

### 1. Certificate Expiration Monitoring

Add Prometheus rules to monitor certificate expiration:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: certificate-expiry
spec:
  groups:
  - name: certificate-expiry
    rules:
    - alert: CertificateExpiry
      expr: probe_ssl_earliest_cert_expiry - time() < 86400 * 7
      for: 5m
      annotations:
        summary: "Certificate expiring soon"
```

### 2. Grafana Dashboard

Import certificate monitoring dashboard:
- Dashboard ID: 11001 (cert-manager)
- Configure data source as Prometheus

## Advanced Configuration

### 1. Multiple Domains

For multiple domains, create separate ClusterIssuers:

```hcl
# Additional domain configuration
variable "additional_domains" {
  type = list(object({
    name    = string
    zone_id = string
  }))
  default = [
    {
      name    = "anotherdomain.com"
      zone_id = "another-zone-id"
    }
  ]
}
```

### 2. Custom Certificate Templates

Create certificate templates for different use cases:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: custom-certificate
spec:
  secretName: custom-certificate-tls
  duration: 2160h # 90 days
  renewBefore: 360h # 15 days
  subject:
    organizations:
      - Your Organization
  isCA: false
  privateKey:
    algorithm: RSA
    encoding: PKCS1
    size: 2048
  usages:
    - server auth
    - client auth
  dnsNames:
    - api.yourdomain.com
    - app.yourdomain.com
```

### 3. External DNS Integration

Automatically create DNS records with external-dns:

```yaml
apiVersion: v1
kind: Service
metadata:
  annotations:
    external-dns.alpha.kubernetes.io/hostname: api.yourdomain.com
spec:
  type: LoadBalancer
```

## Migration from HTTP Challenge

If migrating from HTTP to DNS challenge:

1. **Update ClusterIssuer** to use DNS01 solver
2. **Delete existing certificates** to force recreation
3. **Update ingress annotations** if needed
4. **Verify DNS records** are created automatically

## Cost Considerations

### Cloudflare Costs
- **Free Plan**: 1,000 DNS queries per month
- **Pro Plan**: $20/month for enhanced features
- **Business Plan**: $200/month for advanced security

### Certificate Costs
- **Let's Encrypt**: Free (DNS challenges included)
- **Rate Limits**: 50 certificates per registered domain per week

## Backup and Recovery

### 1. Certificate Backup

```bash
# Backup certificate secrets
kubectl get secret wildcard-yourdomain-com-tls -o yaml > certificate-backup.yaml
```

### 2. Recovery Process

```bash
# Restore certificate secret
kubectl apply -f certificate-backup.yaml

# Force certificate renewal if needed
kubectl delete certificaterequest --all -n production
kubectl delete certificate wildcard-yourdomain-com -n production
kubectl apply -f wildcard-certificate.yaml
```

## Support and Resources

- **cert-manager Documentation**: https://cert-manager.io/docs/
- **Cloudflare API Documentation**: https://api.cloudflare.com/
- **Let's Encrypt Documentation**: https://letsencrypt.org/docs/
- **Kubernetes Certificate Management**: https://kubernetes.io/docs/concepts/configuration/secret/#tls-secrets

For issues specific to this setup, check:
1. Terraform logs: `terraform plan -detailed-exitcode`
2. Kubernetes events: `kubectl get events --sort-by=.metadata.creationTimestamp`
3. cert-manager logs: `kubectl logs -n cert-manager deployment/cert-manager`
