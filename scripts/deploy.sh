#!/bin/bash

set -e

ENVIRONMENT=${1:-staging}
NAMESPACE=${1:-staging}

echo "Deploying to $ENVIRONMENT environment..."

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(staging|production)$ ]]; then
    echo "Error: Environment must be either 'staging' or 'production'"
    exit 1
fi

# Build and push images
echo "Building and pushing Docker images..."
docker build -t monorepocontainerregistry.azurecr.io/api:latest ./apps/api
docker build -t monorepocontainerregistry.azurecr.io/frontend:latest ./apps/frontend

docker push monorepocontainerregistry.azurecr.io/api:latest
docker push monorepocontainerregistry.azurecr.io/frontend:latest

# Deploy with Helm
echo "Deploying API to $ENVIRONMENT..."
helm upgrade --install api-$ENVIRONMENT \
    ./infrastructure/helm/api \
    --namespace $NAMESPACE \
    --create-namespace \
    --values ./infrastructure/helm/api/values-$ENVIRONMENT.yaml \
    --wait

echo "Deploying Frontend to $ENVIRONMENT..."
helm upgrade --install frontend-$ENVIRONMENT \
    ./infrastructure/helm/frontend \
    --namespace $NAMESPACE \
    --create-namespace \
    --values ./infrastructure/helm/frontend/values-$ENVIRONMENT.yaml \
    --wait

echo "Deployment completed successfully!"