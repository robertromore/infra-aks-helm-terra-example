#!/bin/bash

ENVIRONMENT=${1:-staging}
NAMESPACE=${1:-staging}

echo "Cleaning up $ENVIRONMENT environment..."

# Delete Helm releases
helm uninstall api-$ENVIRONMENT --namespace $NAMESPACE || true
helm uninstall frontend-$ENVIRONMENT --namespace $NAMESPACE || true

# Delete namespace
kubectl delete namespace $NAMESPACE || true

echo "Cleanup completed!"