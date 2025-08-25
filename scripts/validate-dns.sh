#!/bin/bash

# DNS Validation and Certificate Management Script
# This script validates Cloudflare DNS setup and cert-manager certificate status

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DOMAIN_NAME="${DOMAIN_NAME:-example.com}"
CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"
CLOUDFLARE_ZONE_ID="${CLOUDFLARE_ZONE_ID:-}"
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
    local tools=("kubectl" "dig" "curl" "jq")
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
    if [[ -z "$DOMAIN_NAME" ]]; then
        log_error "DOMAIN_NAME environment variable is not set"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

validate_cloudflare_api() {
    log_info "Validating Cloudflare API connectivity..."

    if [[ -z "$CLOUDFLARE_API_TOKEN" ]]; then
        log_warning "CLOUDFLARE_API_TOKEN not set, skipping API validation"
        return 0
    fi

    # Test API connectivity
    local response=$(curl -s -w "%{http_code}" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        "https://api.cloudflare.com/client/v4/user/tokens/verify" -o /tmp/cf_response.json)

    if [[ "$response" == "200" ]]; then
        log_success "Cloudflare API token is valid"
        local token_status=$(jq -r '.result.status' /tmp/cf_response.json 2>/dev/null || echo "unknown")
        log_info "Token status: $token_status"
    else
        log_error "Cloudflare API token validation failed (HTTP $response)"
        if [[ -f /tmp/cf_response.json ]]; then
            local error_msg=$(jq -r '.errors[0].message' /tmp/cf_response.json 2>/dev/null || echo "Unknown error")
            log_error "Error: $error_msg"
        fi
        return 1
    fi

    # Clean up temp file
    rm -f /tmp/cf_response.json
}

validate_zone_access() {
    log_info "Validating Cloudflare zone access..."

    if [[ -z "$CLOUDFLARE_API_TOKEN" || -z "$CLOUDFLARE_ZONE_ID" ]]; then
        log_warning "Cloudflare credentials not set, skipping zone validation"
        return 0
    fi

    local response=$(curl -s -w "%{http_code}" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID" -o /tmp/zone_response.json)

    if [[ "$response" == "200" ]]; then
        local zone_name=$(jq -r '.result.name' /tmp/zone_response.json 2>/dev/null || echo "unknown")
        local zone_status=$(jq -r '.result.status' /tmp/zone_response.json 2>/dev/null || echo "unknown")
        log_success "Zone access validated: $zone_name (status: $zone_status)"
    else
        log_error "Zone access validation failed (HTTP $response)"
        return 1
    fi

    rm -f /tmp/zone_response.json
}

check_dns_records() {
    log_info "Checking DNS records for domain: $DOMAIN_NAME"

    # Get load balancer IP
    local lb_ip=$(kubectl get service -n traefik-system traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    if [[ -z "$lb_ip" ]]; then
        log_warning "Load balancer IP not found or not ready"
    else
        log_info "Load balancer IP: $lb_ip"
    fi

    # Check main domain
    log_info "Checking A record for $DOMAIN_NAME..."
    local domain_ip=$(dig +short A $DOMAIN_NAME @8.8.8.8 | head -n1)
    if [[ -n "$domain_ip" ]]; then
        log_success "Domain $DOMAIN_NAME resolves to: $domain_ip"
        if [[ "$domain_ip" == "$lb_ip" ]]; then
            log_success "Domain points to correct load balancer IP"
        elif [[ -n "$lb_ip" ]]; then
            log_warning "Domain points to $domain_ip but load balancer is $lb_ip"
        fi
    else
        log_warning "Domain $DOMAIN_NAME does not resolve"
    fi

    # Check subdomains
    local subdomains=("api" "app" "grafana")
    for subdomain in "${subdomains[@]}"; do
        local full_domain="$subdomain.$DOMAIN_NAME"
        log_info "Checking A record for $full_domain..."

        local sub_ip=$(dig +short A $full_domain @8.8.8.8 | head -n1)
        if [[ -n "$sub_ip" ]]; then
            log_success "$full_domain resolves to: $sub_ip"
        else
            log_warning "$full_domain does not resolve"
        fi
    done
}

validate_cert_manager() {
    log_info "Validating cert-manager installation..."

    # Check if cert-manager namespace exists
    if ! kubectl get namespace cert-manager &> /dev/null; then
        log_error "cert-manager namespace not found"
        return 1
    fi

    # Check cert-manager pods
    local cert_manager_pods=$(kubectl get pods -n cert-manager --no-headers 2>/dev/null | wc -l)
    if [[ "$cert_manager_pods" -gt 0 ]]; then
        log_success "cert-manager namespace found with $cert_manager_pods pods"

        # Check pod status
        local running_pods=$(kubectl get pods -n cert-manager --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        log_info "Running pods: $running_pods/$cert_manager_pods"

        if [[ "$running_pods" == "$cert_manager_pods" ]]; then
            log_success "All cert-manager pods are running"
        else
            log_warning "Not all cert-manager pods are running"
            kubectl get pods -n cert-manager
        fi
    else
        log_error "No cert-manager pods found"
        return 1
    fi
}

check_cluster_issuers() {
    log_info "Checking ClusterIssuers..."

    local issuers=("letsencrypt-staging" "letsencrypt-prod")
    for issuer in "${issuers[@]}"; do
        if kubectl get clusterissuer $issuer &> /dev/null; then
            local ready=$(kubectl get clusterissuer $issuer -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
            if [[ "$ready" == "True" ]]; then
                log_success "ClusterIssuer '$issuer' is ready"
            else
                log_error "ClusterIssuer '$issuer' is not ready (status: $ready)"
                kubectl describe clusterissuer $issuer | tail -20
            fi
        else
            log_error "ClusterIssuer '$issuer' not found"
        fi
    done
}

check_cloudflare_secret() {
    log_info "Checking Cloudflare API secret..."

    if kubectl get secret cloudflare-api-token-secret -n cert-manager &> /dev/null; then
        log_success "Cloudflare API secret found in cert-manager namespace"

        # Check if secret has required key
        local has_token=$(kubectl get secret cloudflare-api-token-secret -n cert-manager -o jsonpath='{.data.api-token}' 2>/dev/null)
        if [[ -n "$has_token" ]]; then
            log_success "Secret contains api-token key"
        else
            log_error "Secret missing api-token key"
            return 1
        fi
    else
        log_error "Cloudflare API secret not found in cert-manager namespace"
        return 1
    fi
}

check_certificates() {
    log_info "Checking certificates..."

    # Check if certificates exist
    local cert_name="wildcard-$(echo $DOMAIN_NAME | tr '.' '-')"

    # Check in multiple namespaces
    local namespaces=("default" "production" "staging")
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace $ns &> /dev/null; then
            log_info "Checking certificates in namespace: $ns"

            if kubectl get certificate $cert_name -n $ns &> /dev/null; then
                local ready=$(kubectl get certificate $cert_name -n $ns -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
                local not_after=$(kubectl get certificate $cert_name -n $ns -o jsonpath='{.status.notAfter}' 2>/dev/null || echo "Unknown")

                if [[ "$ready" == "True" ]]; then
                    log_success "Certificate '$cert_name' in namespace '$ns' is ready (expires: $not_after)"
                else
                    log_error "Certificate '$cert_name' in namespace '$ns' is not ready"
                    kubectl describe certificate $cert_name -n $ns | tail -10
                fi
            else
                log_warning "Certificate '$cert_name' not found in namespace '$ns'"
            fi
        fi
    done
}

check_certificate_requests() {
    log_info "Checking recent certificate requests..."

    local cert_requests=$(kubectl get certificaterequests -A --sort-by=.metadata.creationTimestamp --no-headers 2>/dev/null | tail -5)

    if [[ -n "$cert_requests" ]]; then
        log_info "Recent certificate requests:"
        echo "$cert_requests"
        echo ""

        # Check status of recent requests
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                local ns=$(echo "$line" | awk '{print $1}')
                local name=$(echo "$line" | awk '{print $2}')
                local ready=$(echo "$line" | awk '{print $3}')

                if [[ "$ready" == "True" ]]; then
                    log_success "Certificate request '$name' in '$ns' is approved"
                else
                    log_warning "Certificate request '$name' in '$ns' status: $ready"
                fi
            fi
        done <<< "$cert_requests"
    else
        log_warning "No certificate requests found"
    fi
}

test_dns_challenge() {
    log_info "Testing DNS challenge capability..."

    if [[ -z "$CLOUDFLARE_API_TOKEN" ]]; then
        log_warning "Cannot test DNS challenge without Cloudflare API token"
        return 0
    fi

    # Create a test TXT record
    local test_name="_acme-challenge-test"
    local test_value="test-$(date +%s)"

    log_info "Creating test TXT record: $test_name.$DOMAIN_NAME"

    local create_response=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"TXT\",\"name\":\"$test_name\",\"content\":\"$test_value\",\"ttl\":120}")

    local record_id=$(echo "$create_response" | jq -r '.result.id' 2>/dev/null)

    if [[ "$record_id" != "null" && -n "$record_id" ]]; then
        log_success "Test TXT record created with ID: $record_id"

        # Wait for DNS propagation
        log_info "Waiting for DNS propagation (30 seconds)..."
        sleep 30

        # Test DNS resolution
        local resolved_value=$(dig +short TXT "$test_name.$DOMAIN_NAME" @8.8.8.8 | tr -d '"')
        if [[ "$resolved_value" == "$test_value" ]]; then
            log_success "DNS challenge test successful - record resolves correctly"
        else
            log_warning "DNS challenge test failed - record not resolving (got: '$resolved_value', expected: '$test_value')"
        fi

        # Clean up test record
        log_info "Cleaning up test record..."
        curl -s -X DELETE \
            "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$record_id" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" > /dev/null

        log_success "Test record cleaned up"
    else
        log_error "Failed to create test TXT record"
        echo "$create_response" | jq '.' 2>/dev/null || echo "$create_response"
    fi
}

check_certificate_events() {
    log_info "Checking certificate-related events..."

    # Get recent events related to certificates
    local cert_events=$(kubectl get events --all-namespaces \
        --field-selector reason!=Scheduled,reason!=Created,reason!=Started \
        --sort-by=.metadata.creationTimestamp \
        | grep -i -E "(certificate|issuer|challenge)" | tail -10 || echo "")

    if [[ -n "$cert_events" ]]; then
        log_info "Recent certificate-related events:"
        echo "$cert_events"
    else
        log_info "No recent certificate-related events found"
    fi
}

generate_dns_report() {
    log_info "Generating DNS validation report..."

    echo ""
    echo "=== DNS Validation Report ==="
    echo "Domain: $DOMAIN_NAME"
    echo "Environment: $ENVIRONMENT"
    echo "Timestamp: $(date)"
    echo ""

    echo "=== DNS Resolution ==="
    echo "Domain: $(dig +short A $DOMAIN_NAME @8.8.8.8 | head -n1 || echo 'Not resolved')"
    echo "API: $(dig +short A api.$DOMAIN_NAME @8.8.8.8 | head -n1 || echo 'Not resolved')"
    echo "App: $(dig +short A app.$DOMAIN_NAME @8.8.8.8 | head -n1 || echo 'Not resolved')"
    echo "Grafana: $(dig +short A grafana.$DOMAIN_NAME @8.8.8.8 | head -n1 || echo 'Not resolved')"
    echo ""

    echo "=== Load Balancer ==="
    local lb_ip=$(kubectl get service -n traefik-system traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Not found")
    echo "Traefik LB IP: $lb_ip"
    echo ""

    echo "=== ClusterIssuers ==="
    kubectl get clusterissuers -o custom-columns=NAME:.metadata.name,READY:.status.conditions[?(@.type==\"Ready\")].status,AGE:.metadata.creationTimestamp 2>/dev/null || echo "No ClusterIssuers found"
    echo ""

    echo "=== Certificates ==="
    kubectl get certificates -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[?(@.type==\"Ready\")].status,SECRET:.spec.secretName,AGE:.metadata.creationTimestamp 2>/dev/null || echo "No certificates found"
    echo ""

    echo "=== Certificate Secrets ==="
    kubectl get secrets -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,TYPE:.type,AGE:.metadata.creationTimestamp | grep tls || echo "No TLS secrets found"
    echo ""
}

main() {
    log_info "Starting DNS validation for domain: $DOMAIN_NAME (environment: $ENVIRONMENT)"
    echo ""

    check_prerequisites
    echo ""

    validate_cloudflare_api
    echo ""

    validate_zone_access
    echo ""

    check_dns_records
    echo ""

    validate_cert_manager
    echo ""

    check_cluster_issuers
    echo ""

    check_cloudflare_secret
    echo ""

    check_certificates
    echo ""

    check_certificate_requests
    echo ""

    test_dns_challenge
    echo ""

    check_certificate_events
    echo ""

    generate_dns_report

    log_success "DNS validation completed!"
    echo ""
    echo "Next steps:"
    echo "1. If certificates are not ready, check cert-manager logs: kubectl logs -n cert-manager deployment/cert-manager"
    echo "2. Monitor certificate status: kubectl get certificates -A -w"
    echo "3. Test HTTPS endpoints once certificates are ready"
    echo "4. Check Cloudflare dashboard for DNS challenge records"
}

# Handle script arguments
case "${1:-help}" in
    "help"|"-h"|"--help")
        echo "Usage: $0 [ENVIRONMENT]"
        echo ""
        echo "Validates DNS setup and certificate management for Cloudflare"
        echo ""
        echo "Arguments:"
        echo "  ENVIRONMENT    Target environment (default: staging)"
        echo ""
        echo "Required Environment Variables:"
        echo "  DOMAIN_NAME              Your domain name (e.g., example.com)"
        echo "  CLOUDFLARE_API_TOKEN     Cloudflare API token (optional for some checks)"
        echo "  CLOUDFLARE_ZONE_ID       Cloudflare zone ID (optional for some checks)"
        echo ""
        echo "Examples:"
        echo "  DOMAIN_NAME=example.com $0 staging"
        echo "  DOMAIN_NAME=example.com CLOUDFLARE_API_TOKEN=token $0 production"
        echo ""
        echo "DNS Challenge Test:"
        echo "  The script will create and test a temporary TXT record if Cloudflare"
        echo "  credentials are provided. This verifies DNS challenge capability."
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
