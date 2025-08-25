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

# Build and push images to GHCR
echo "Building and pushing Docker images to GitHub Container Registry..."

# Login to GHCR
echo $GITHUB_TOKEN | docker login ghcr.io -u $GITHUB_USERNAME --password-stdin

# Get repository name (assumes script is run from repo root)
REPO_NAME=$(basename -s .git $(git config --get remote.origin.url) 2>/dev/null || echo "your-repo-name")

docker build -t ghcr.io/$GITHUB_USERNAME/$REPO_NAME/api:latest ./apps/api
docker build -t ghcr.io/$GITHUB_USERNAME/$REPO_NAME/frontend:latest ./apps/frontend

docker push ghcr.io/$GITHUB_USERNAME/$REPO_NAME/api:latest
docker push ghcr.io/$GITHUB_USERNAME/$REPO_NAME/frontend:latest

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
