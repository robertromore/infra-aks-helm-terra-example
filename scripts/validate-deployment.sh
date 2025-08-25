#!/bin/bash

# GHCR Deployment Validation Script
# This script validates that the GHCR migration and deployment are working correctly

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GITHUB_USERNAME="${GITHUB_USERNAME:-}"
REPO_NAME="${REPO_NAME:-}"
ENVIRONMENT="${1:-staging}"
NAMESPACE="${ENVIRONMENT}"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if required tools are installed
    local tools=("kubectl" "helm" "docker" "curl")
    for tool in "${tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            log_error "$tool is not installed or not in PATH"
            exit 1
        fi
    done

    # Check if kubectl is configured
    if ! kubectl cluster-info &> /dev/null; then
        log_error "kubectl is not configured or cluster is not accessible"
        exit 1
    fi

    # Check environment variables
    if [[ -z "$GITHUB_USERNAME" ]]; then
        log_error "GITHUB_USERNAME environment variable is not set"
        exit 1
    fi

    if [[ -z "$REPO_NAME" ]]; then
        log_warning "REPO_NAME not set, trying to detect from git remote..."
        REPO_NAME=$(basename -s .git $(git config --get remote.origin.url) 2>/dev/null || echo "")
        if [[ -z "$REPO_NAME" ]]; then
            log_error "Could not determine repository name. Set REPO_NAME environment variable."
            exit 1
        fi
    fi

    log_success "Prerequisites check passed"
}

validate_ghcr_connectivity() {
    log_info "Validating GHCR connectivity..."

    # Test GHCR API connectivity
    if curl -s -f -H "Authorization: Bearer ${GITHUB_TOKEN:-}" \
       "https://ghcr.io/v2/token?service=ghcr.io" > /dev/null; then
        log_success "GHCR API is accessible"
    else
        log_warning "GHCR API test failed (this may be normal without authentication)"
    fi

    # Test Docker login to GHCR
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        if echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_USERNAME" --password-stdin &> /dev/null; then
            log_success "Docker login to GHCR successful"
        else
            log_error "Docker login to GHCR failed"
            return 1
        fi
    else
        log_warning "GITHUB_TOKEN not set, skipping Docker login test"
    fi
}

check_image_availability() {
    log_info "Checking image availability in GHCR..."

    local images=("api" "frontend")
    for image in "${images[@]}"; do
        local image_url="ghcr.io/$GITHUB_USERNAME/$REPO_NAME/$image:latest"
        log_info "Checking image: $image_url"

        if docker pull "$image_url" &> /dev/null; then
            log_success "Image $image is available and pullable"
            # Clean up pulled image
            docker rmi "$image_url" &> /dev/null || true
        else
            log_error "Failed to pull image: $image_url"
            return 1
        fi
    done
}

validate_kubernetes_secrets() {
    log_info "Validating Kubernetes pull secrets..."

    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_warning "Namespace '$NAMESPACE' does not exist"
        return 1
    fi

    # Check if pull secret exists
    if kubectl get secret ghcr-pull-secret -n "$NAMESPACE" &> /dev/null; then
        log_success "GHCR pull secret exists in namespace '$NAMESPACE'"

        # Validate secret format
        local secret_data=$(kubectl get secret ghcr-pull-secret -n "$NAMESPACE" -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d)
        if echo "$secret_data" | jq -e '.auths."ghcr.io"' &> /dev/null; then
            log_success "Pull secret is properly formatted"
        else
            log_error "Pull secret is not properly formatted"
            return 1
        fi
    else
        log_error "GHCR pull secret does not exist in namespace '$NAMESPACE'"
        return 1
    fi
}

validate_helm_deployments() {
    log_info "Validating Helm deployments..."

    local releases=("api-$ENVIRONMENT" "frontend-$ENVIRONMENT")
    for release in "${releases[@]}"; do
        if helm status "$release" -n "$NAMESPACE" &> /dev/null; then
            local status=$(helm status "$release" -n "$NAMESPACE" -o json | jq -r '.info.status')
            if [[ "$status" == "deployed" ]]; then
                log_success "Helm release '$release' is deployed successfully"
            else
                log_error "Helm release '$release' status is '$status'"
                return 1
            fi
        else
            log_warning "Helm release '$release' not found"
        fi
    done
}

validate_pod_status() {
    log_info "Validating pod status..."

    # Get pods in the namespace
    local pods=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null || echo "")
    if [[ -z "$pods" ]]; then
        log_warning "No pods found in namespace '$NAMESPACE'"
        return 1
    fi

    # Check each pod
    while IFS= read -r line; do
        local pod_name=$(echo "$line" | awk '{print $1}')
        local ready=$(echo "$line" | awk '{print $2}')
        local status=$(echo "$line" | awk '{print $3}')

        if [[ "$status" == "Running" ]] && [[ "$ready" =~ ^[1-9]/[1-9] ]]; then
            log_success "Pod '$pod_name' is running and ready"
        else
            log_error "Pod '$pod_name' status: $status, ready: $ready"

            # Show pod events for troubleshooting
            log_info "Recent events for pod '$pod_name':"
            kubectl describe pod "$pod_name" -n "$NAMESPACE" | tail -10
            return 1
        fi
    done <<< "$pods"
}

validate_image_pull_success() {
    log_info "Validating image pull events..."

    # Check for image pull errors in events
    local pull_errors=$(kubectl get events -n "$NAMESPACE" --field-selector reason=Failed --no-headers 2>/dev/null | grep -i "pull" || echo "")
    if [[ -n "$pull_errors" ]]; then
        log_error "Image pull errors detected:"
        echo "$pull_errors"
        return 1
    else
        log_success "No image pull errors detected"
    fi

    # Check for successful pulls
    local successful_pulls=$(kubectl get events -n "$NAMESPACE" --field-selector reason=Pulled --no-headers 2>/dev/null | grep -c "ghcr.io" || echo "0")
    if [[ "$successful_pulls" -gt 0 ]]; then
        log_success "Found $successful_pulls successful GHCR image pulls"
    else
        log_warning "No successful GHCR image pulls found in recent events"
    fi
}

validate_ingress() {
    log_info "Validating ingress configuration..."

    # Check if ingresses exist
    local ingresses=$(kubectl get ingress -n "$NAMESPACE" --no-headers 2>/dev/null || echo "")
    if [[ -z "$ingresses" ]]; then
        log_warning "No ingresses found in namespace '$NAMESPACE'"
        return 0
    fi

    # Check each ingress
    while IFS= read -r line; do
        local ingress_name=$(echo "$line" | awk '{print $1}')
        local class=$(echo "$line" | awk '{print $2}')
        local hosts=$(echo "$line" | awk '{print $3}')
        local address=$(echo "$line" | awk '{print $4}')

        if [[ "$class" == "traefik" ]]; then
            log_success "Ingress '$ingress_name' using Traefik class"
        else
            log_warning "Ingress '$ingress_name' using class '$class' (expected: traefik)"
        fi

        if [[ -n "$address" && "$address" != "<none>" ]]; then
            log_success "Ingress '$ingress_name' has external address: $address"
        else
            log_warning "Ingress '$ingress_name' has no external address yet"
        fi
    done <<< "$ingresses"
}

validate_services() {
    log_info "Validating services..."

    local services=$(kubectl get services -n "$NAMESPACE" --no-headers 2>/dev/null || echo "")
    if [[ -z "$services" ]]; then
        log_warning "No services found in namespace '$NAMESPACE'"
        return 0
    fi

    while IFS= read -r line; do
        local service_name=$(echo "$line" | awk '{print $1}')
        local type=$(echo "$line" | awk '{print $2}')
        local cluster_ip=$(echo "$line" | awk '{print $3}')
        local external_ip=$(echo "$line" | awk '{print $4}')
        local ports=$(echo "$line" | awk '{print $5}')

        if [[ "$cluster_ip" != "<none>" ]]; then
            log_success "Service '$service_name' ($type) has cluster IP: $cluster_ip"
        else
            log_error "Service '$service_name' has no cluster IP"
            return 1
        fi
    done <<< "$services"
}

generate_report() {
    log_info "Generating deployment report..."

    echo ""
    echo "=== GHCR Deployment Validation Report ==="
    echo "Environment: $ENVIRONMENT"
    echo "Namespace: $NAMESPACE"
    echo "GitHub Repository: $GITHUB_USERNAME/$REPO_NAME"
    echo "Timestamp: $(date)"
    echo ""

    echo "=== Cluster Information ==="
    kubectl cluster-info
    echo ""

    echo "=== Namespace Resources ==="
    kubectl get all -n "$NAMESPACE" 2>/dev/null || echo "No resources found"
    echo ""

    echo "=== GHCR Pull Secrets ==="
    kubectl get secrets -n "$NAMESPACE" | grep ghcr || echo "No GHCR secrets found"
    echo ""

    echo "=== Recent Events ==="
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -20 2>/dev/null || echo "No events found"
    echo ""
}

main() {
    log_info "Starting GHCR deployment validation for environment: $ENVIRONMENT"
    echo ""

    check_prerequisites
    echo ""

    validate_ghcr_connectivity
    echo ""

    check_image_availability
    echo ""

    validate_kubernetes_secrets
    echo ""

    validate_helm_deployments
    echo ""

    validate_pod_status
    echo ""

    validate_image_pull_success
    echo ""

    validate_ingress
    echo ""

    validate_services
    echo ""

    generate_report

    log_success "GHCR deployment validation completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Test application endpoints if ingresses are configured"
    echo "2. Monitor application logs: kubectl logs -f deployment/api-$ENVIRONMENT -n $NAMESPACE"
    echo "3. Check Traefik dashboard: kubectl port-forward -n traefik-system svc/traefik 8080:8080"
}

# Handle script arguments
case "${1:-help}" in
    "help"|"-h"|"--help")
        echo "Usage: $0 [ENVIRONMENT]"
        echo ""
        echo "Validates GHCR deployment for the specified environment"
        echo ""
        echo "Arguments:"
        echo "  ENVIRONMENT    Target environment (default: staging)"
        echo ""
        echo "Required Environment Variables:"
        echo "  GITHUB_USERNAME    Your GitHub username"
        echo "  REPO_NAME         Repository name (auto-detected if not set)"
        echo "  GITHUB_TOKEN      GitHub Personal Access Token (optional)"
        echo ""
        echo "Examples:"
        echo "  $0 staging"
        echo "  $0 production"
        echo "  GITHUB_USERNAME=myuser REPO_NAME=myrepo $0 production"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
