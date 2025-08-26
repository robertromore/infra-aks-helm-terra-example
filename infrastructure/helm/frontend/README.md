# Next.js Frontend Helm Chart

This Helm chart deploys a Next.js frontend application on Kubernetes with production-ready features including autoscaling, health checks, security configurations, and API integration.

## Features

- **Next.js SSR/SSG Support**: Optimized for server-side rendering and static site generation
- **Horizontal Pod Autoscaling**: Automatic scaling based on CPU/memory usage
- **Health Checks**: Comprehensive liveness, readiness, and startup probes
- **API Integration**: Seamless connection to backend APIs (Laravel or others)
- **Security**: Pod security contexts, network policies, and security headers
- **High Availability**: Pod disruption budgets and anti-affinity rules
- **Performance**: Optimized caching, resource management, and build configurations
- **Monitoring**: Prometheus metrics and observability ready

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2.0+
- Next.js application with health check endpoint
- Container registry access (GHCR, Docker Hub, etc.)

## Installation

### Quick Start

```bash
# Install with default configuration
helm install my-frontend . \
  --set image.repository=your-registry/nextjs-app \
  --set image.tag=latest \
  --set ingress.hosts[0].host=app.your-domain.com
```

### Production Deployment

```bash
# Install with production settings
helm install my-frontend . \
  --values values.yaml \
  --values values-production.yaml \
  --set image.repository=your-registry/nextjs-app \
  --set image.tag=v1.0.0
```

## Configuration

### Global Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | Container image repository | `ghcr.io/GITHUB_USERNAME/REPO_NAME/frontend` |
| `image.tag` | Container image tag | `latest` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `replicaCount` | Number of pod replicas | `2` |
| `nodeEnv` | Node.js environment | `production` |

### Service Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `service.type` | Kubernetes service type | `ClusterIP` |
| `service.port` | Service port | `80` |
| `service.targetPort` | Container target port | `3000` |

### Ingress Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ingress.enabled` | Enable ingress | `true` |
| `ingress.className` | Ingress class name | `traefik` |
| `ingress.hosts[0].host` | Hostname | `app.example.com` |
| `ingress.tls[0].secretName` | TLS secret name | `frontend-tls` |

### Resource Management

| Parameter | Description | Default |
|-----------|-------------|---------|
| `resources.limits.cpu` | CPU limit | `500m` |
| `resources.limits.memory` | Memory limit | `512Mi` |
| `resources.requests.cpu` | CPU request | `200m` |
| `resources.requests.memory` | Memory request | `256Mi` |

### Autoscaling

| Parameter | Description | Default |
|-----------|-------------|---------|
| `autoscaling.enabled` | Enable horizontal pod autoscaling | `true` |
| `autoscaling.minReplicas` | Minimum number of replicas | `2` |
| `autoscaling.maxReplicas` | Maximum number of replicas | `10` |
| `autoscaling.targetCPUUtilizationPercentage` | Target CPU utilization | `80` |

### Health Checks

| Parameter | Description | Default |
|-----------|-------------|---------|
| `healthcheck.enabled` | Enable health checks | `true` |
| `healthcheck.path` | Health check endpoint | `/api/health` |
| `healthcheck.liveness.initialDelaySeconds` | Liveness probe initial delay | `30` |
| `healthcheck.readiness.initialDelaySeconds` | Readiness probe initial delay | `10` |

### API Integration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `api.external.enabled` | Use external API | `true` |
| `api.external.url` | External API URL | `http://api.example.com` |

### Next.js Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `nextjs.build.standalone` | Enable Next.js standalone output | `true` |
| `nextjs.build.tracing` | Enable tracing | `false` |
| `nextjs.optimization.bundleAnalyzer` | Enable bundle analyzer | `false` |

## Environment Variables

The chart supports various environment variables for Next.js applications:

```yaml
env:
  - name: NEXT_PUBLIC_APP_URL
    value: "https://app.your-domain.com"
  - name: NEXT_PUBLIC_API_URL
    value: "https://api.your-domain.com"
  - name: NEXT_PUBLIC_ENVIRONMENT
    value: "production"
  - name: NEXT_TELEMETRY_DISABLED
    value: "1"
```

## Health Check Endpoint

Your Next.js application should provide a health check endpoint. Create `pages/api/health.js` (or `app/api/health/route.js` for App Router):

```javascript
// pages/api/health.js
export default function handler(req, res) {
  res.status(200).json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
}

// or app/api/health/route.js (App Router)
export async function GET() {
  return Response.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
}
```

## Docker Configuration

Ensure your Next.js application is configured for containerization:

### Dockerfile Example

```dockerfile
FROM node:18-alpine AS base

# Install dependencies only when needed
FROM base AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app

# Install dependencies
COPY package.json package-lock.json* ./
RUN npm ci --only=production

# Rebuild the source code only when needed
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Build with standalone output
RUN npm run build

# Production image, copy all the files and run next
FROM base AS runner
WORKDIR /app

ENV NODE_ENV production
ENV NEXT_TELEMETRY_DISABLED 1

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Copy standalone build
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/.next/cache ./.next/cache

USER nextjs

EXPOSE 3000

ENV PORT 3000
ENV HOSTNAME "0.0.0.0"

CMD ["node", "server.js"]
```

### Next.js Configuration

Configure your `next.config.js` for containerization:

```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',
  experimental: {
    outputFileTracingRoot: path.join(__dirname, '../../'),
  },
  // Disable telemetry in containers
  telemetry: false,
  // Security headers
  async headers() {
    return [
      {
        source: '/(.*)',
        headers: [
          {
            key: 'X-Content-Type-Options',
            value: 'nosniff',
          },
          {
            key: 'X-Frame-Options',
            value: 'DENY',
          },
          {
            key: 'X-XSS-Protection',
            value: '1; mode=block',
          },
        ],
      },
    ];
  },
};

module.exports = nextConfig;
```

## Production Deployment

### Production Values

For production deployments, use the `values-production.yaml` file which includes:

- Higher replica count (5 pods)
- Increased resource allocations
- Production SSL certificates
- Enhanced security configurations
- Network policies
- Topology spread constraints
- Performance optimizations

```bash
helm upgrade --install my-frontend . \
  --values values.yaml \
  --values values-production.yaml \
  --set image.tag=v1.0.0
```

### Environment-Specific Configurations

#### Staging Environment

```yaml
# values-staging.yaml
replicaCount: 3
nodeEnv: staging

ingress:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-staging"
  hosts:
    - host: staging-app.your-domain.com

env:
  - name: NEXT_PUBLIC_ENVIRONMENT
    value: "staging"
  - name: NEXT_PUBLIC_API_URL
    value: "https://staging-api.your-domain.com"
```

#### Development Environment

```yaml
# values-dev.yaml
replicaCount: 1
nodeEnv: development

resources:
  limits:
    cpu: 250m
    memory: 256Mi
  requests:
    cpu: 100m
    memory: 128Mi

autoscaling:
  enabled: false
```

## API Integration

### Internal API (Same Cluster)

When your API runs in the same Kubernetes cluster:

```yaml
api:
  external:
    enabled: false
  internal:
    serviceName: "my-api"
    namespace: "default"
    port: 80
```

### External API

For external APIs or different clusters:

```yaml
api:
  external:
    enabled: true
    url: "https://api.your-domain.com"
```

## Security Features

### Network Policies

The chart includes network policies for production environments:

```yaml
networkPolicy:
  enabled: true
  policyTypes:
    - Ingress
    - Egress
  # Restrict ingress to Traefik only
  # Allow egress for API calls and DNS
```

### Security Contexts

Containers run with security constraints:

```yaml
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 1001
  capabilities:
    drop:
    - ALL
```

## Monitoring and Observability

### Metrics Endpoint

Add a metrics endpoint to your Next.js application:

```javascript
// pages/api/metrics.js
export default function handler(req, res) {
  const metrics = {
    nodejs_memory_usage_bytes: process.memoryUsage(),
    nodejs_uptime_seconds: process.uptime(),
    http_requests_total: req.headers['x-request-count'] || 0,
  };
  
  res.status(200).json(metrics);
}
```

### Prometheus Configuration

```yaml
monitoring:
  enabled: true
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "3000"
    prometheus.io/path: "/api/metrics"
```

## Troubleshooting

### Common Issues

1. **Build Failures**: Ensure your Dockerfile uses multi-stage builds and standalone output
2. **Health Check Failures**: Verify the `/api/health` endpoint is accessible
3. **API Connection Issues**: Check network policies and service discovery
4. **Memory Issues**: Adjust Node.js memory settings and resource limits

### Debug Commands

```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/instance=my-frontend

# View application logs
kubectl logs deployment/my-frontend -f

# Port forward for local testing
kubectl port-forward service/my-frontend 3000:80

# Check ingress configuration
kubectl describe ingress my-frontend

# Test health endpoint
kubectl exec deployment/my-frontend -- wget -qO- http://localhost:3000/api/health
```

### Performance Optimization

```bash
# Check resource usage
kubectl top pods -l app.kubernetes.io/instance=my-frontend

# Monitor autoscaling
kubectl get hpa my-frontend -w

# View metrics
kubectl get --raw /metrics | grep frontend
```

## Upgrading

```bash
# Upgrade with new image
helm upgrade my-frontend . \
  --reuse-values \
  --set image.tag=v1.1.0

# Upgrade with new configuration
helm upgrade my-frontend . \
  --values values-production.yaml
```

## Uninstalling

```bash
# Uninstall the release
helm uninstall my-frontend

# Clean up persistent data (if any)
kubectl delete pvc -l app.kubernetes.io/instance=my-frontend
```

## Contributing

1. Update chart version in `Chart.yaml`
2. Test changes with `helm template`
3. Validate with `helm lint`
4. Update this documentation

## License

This Helm chart is licensed under the MIT License.