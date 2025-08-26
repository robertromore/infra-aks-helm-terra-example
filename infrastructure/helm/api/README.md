# Laravel API Helm Chart

This Helm chart deploys a Laravel API application on Kubernetes with support for web servers, queue workers, scheduled tasks, and database migrations.

## Features

- **Web Application**: Laravel API server with autoscaling
- **Queue Workers**: Background job processing with Redis
- **Scheduler**: Laravel Cron jobs using Kubernetes CronJobs
- **Database Migration**: Automatic database migrations on deployment
- **Health Checks**: Liveness, readiness, and startup probes
- **Security**: Pod security contexts and service accounts
- **High Availability**: Pod disruption budgets and anti-affinity rules

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2.0+
- PostgreSQL database (can be deployed as dependency or external)
- Redis cache (can be deployed as dependency or external)

## Installation

### Add Required Helm Repositories

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

### Install with Default Configuration

```bash
# Install with internal PostgreSQL and Redis
helm install my-api . \
  --set image.repository=your-registry/laravel-api \
  --set image.tag=latest \
  --set ingress.hosts[0].host=api.your-domain.com
```

### Install for Production

```bash
# Install with external database and production settings
helm install my-api . \
  --values values.yaml \
  --values values-production.yaml \
  --set image.repository=your-registry/laravel-api \
  --set image.tag=v1.0.0
```

## Configuration

The following table lists the configurable parameters and their default values.

### Global Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | Container image repository | `ghcr.io/GITHUB_USERNAME/REPO_NAME/api` |
| `image.tag` | Container image tag | `latest` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `nameOverride` | Override the name of the chart | `""` |
| `fullnameOverride` | Override the full name of the chart | `""` |

### Web Application

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of web pod replicas | `2` |
| `resources.limits.cpu` | CPU limit | `500m` |
| `resources.limits.memory` | Memory limit | `512Mi` |
| `resources.requests.cpu` | CPU request | `250m` |
| `resources.requests.memory` | Memory request | `256Mi` |

### Autoscaling

| Parameter | Description | Default |
|-----------|-------------|---------|
| `autoscaling.enabled` | Enable horizontal pod autoscaling | `true` |
| `autoscaling.minReplicas` | Minimum number of replicas | `2` |
| `autoscaling.maxReplicas` | Maximum number of replicas | `10` |
| `autoscaling.targetCPUUtilizationPercentage` | Target CPU utilization | `80` |
| `autoscaling.targetMemoryUtilizationPercentage` | Target memory utilization | `80` |

### Service Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `service.type` | Kubernetes service type | `ClusterIP` |
| `service.port` | Service port | `80` |
| `service.targetPort` | Container target port | `8000` |

### Ingress Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ingress.enabled` | Enable ingress | `true` |
| `ingress.className` | Ingress class name | `traefik` |
| `ingress.hosts[0].host` | Hostname | `api.example.com` |
| `ingress.tls[0].secretName` | TLS secret name | `api-tls` |

### Queue Workers

| Parameter | Description | Default |
|-----------|-------------|---------|
| `queue.enabled` | Enable queue workers | `true` |
| `queue.replicaCount` | Number of queue worker replicas | `2` |
| `queue.resources.limits.cpu` | CPU limit for queue workers | `200m` |
| `queue.resources.limits.memory` | Memory limit for queue workers | `256Mi` |

### Scheduler

| Parameter | Description | Default |
|-----------|-------------|---------|
| `scheduler.enabled` | Enable Laravel scheduler | `true` |
| `scheduler.schedule` | Cron schedule | `"* * * * *"` |
| `scheduler.resources.limits.cpu` | CPU limit for scheduler | `100m` |
| `scheduler.resources.limits.memory` | Memory limit for scheduler | `128Mi` |

### Database Migration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `databaseMigration.enabled` | Enable automatic database migrations | `true` |
| `databaseMigration.retry` | Number of migration retries | `3` |

### Dependencies

| Parameter | Description | Default |
|-----------|-------------|---------|
| `postgresql.enabled` | Deploy PostgreSQL as dependency | `true` |
| `postgresql.auth.database` | PostgreSQL database name | `laravel` |
| `redis.enabled` | Deploy Redis as dependency | `true` |
| `redis.auth.enabled` | Enable Redis authentication | `false` |

## Environment Variables

The chart supports Laravel environment variables through the `env` array:

```yaml
env:
  - name: APP_ENV
    value: "production"
  - name: APP_DEBUG
    value: "false"
  - name: DB_CONNECTION
    value: "pgsql"
```

## Secrets

Application secrets are managed through the `secrets` object:

```yaml
secrets:
  db-host: "postgresql-host"
  db-database: "laravel"
  db-username: "laravel"
  db-password: "secure-password"
  app-key: "base64:your-app-key"
```

**⚠️ Security Notice**: In production environments, use external secret management solutions like:
- Azure Key Vault
- AWS Secrets Manager
- HashiCorp Vault
- Kubernetes External Secrets Operator

## Production Deployment

For production deployments, create a `values-production.yaml` file:

```yaml
replicaCount: 5

image:
  pullPolicy: Always

resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 500m
    memory: 512Mi

autoscaling:
  minReplicas: 3
  maxReplicas: 20
  targetCPUUtilizationPercentage: 70

# Use external database
postgresql:
  enabled: false

redis:
  enabled: true
  auth:
    enabled: true
    password: "production-redis-password"
```

## Health Checks

The chart includes comprehensive health checks:

- **Startup Probe**: `/health` endpoint with 30 attempts
- **Liveness Probe**: `/health` endpoint every 30 seconds
- **Readiness Probe**: `/health` endpoint every 10 seconds

Ensure your Laravel application provides these endpoints:

```php
// routes/web.php
Route::get('/health', function () {
    return response()->json(['status' => 'healthy']);
});
```

## Troubleshooting

### Common Issues

1. **ImagePullBackOff**: Ensure image pull secrets are configured correctly
2. **Database Connection Failed**: Check database host and credentials
3. **Migration Failed**: Verify database permissions and connectivity

### Debug Commands

```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/instance=my-api

# View pod logs
kubectl logs deployment/my-api

# Check events
kubectl get events --sort-by='.lastTimestamp'

# Port forward for testing
kubectl port-forward service/my-api 8080:80
```

### Accessing Logs

```bash
# Web application logs
kubectl logs -l app.kubernetes.io/component=web -f

# Queue worker logs
kubectl logs -l app.kubernetes.io/component=queue -f

# Scheduler logs
kubectl logs -l app.kubernetes.io/component=scheduler
```

## Scaling

### Manual Scaling

```bash
# Scale web application
kubectl scale deployment my-api --replicas=5

# Scale queue workers
kubectl scale deployment my-api-queue --replicas=3
```

### Horizontal Pod Autoscaler

The chart includes HPA configuration for automatic scaling based on CPU and memory usage.

## Upgrading

```bash
# Upgrade with new image
helm upgrade my-api . \
  --reuse-values \
  --set image.tag=v1.1.0

# Upgrade with new values
helm upgrade my-api . \
  --values values-production.yaml
```

## Uninstalling

```bash
# Uninstall the release
helm uninstall my-api

# Clean up persistent volumes (if needed)
kubectl delete pvc -l app.kubernetes.io/instance=my-api
```

## Contributing

1. Make changes to the chart
2. Update the version in `Chart.yaml`
3. Test the changes with `helm template`
4. Validate with `helm lint`

## License

This Helm chart is licensed under the MIT License.