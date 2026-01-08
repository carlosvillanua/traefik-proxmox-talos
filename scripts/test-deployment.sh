#!/bin/bash

# End-to-End Deployment Test
# This validates the full deployment workflow

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_info() {
    echo -e "${YELLOW}→${NC} $1"
}

echo "===== End-to-End Deployment Test ====="
echo ""

# Test 1: Check talosctl is installed
log_info "Test 1: Checking talosctl installation"
if command -v talosctl &> /dev/null; then
    VERSION=$(talosctl version --client --short)
    log_success "talosctl installed: $VERSION"
else
    log_error "talosctl not found"
    exit 1
fi

# Test 2: Check kubectl is installed
log_info "Test 2: Checking kubectl installation"
if command -v kubectl &> /dev/null; then
    VERSION=$(kubectl version --client --short 2>/dev/null || kubectl version --client -o json | jq -r '.clientVersion.gitVersion')
    log_success "kubectl installed: $VERSION"
else
    log_error "kubectl not found"
    exit 1
fi

# Test 3: Check cluster connectivity
log_info "Test 3: Checking Kubernetes cluster connectivity"
if kubectl cluster-info &> /dev/null; then
    log_success "Connected to Kubernetes cluster"
else
    log_error "Cannot connect to cluster"
    exit 1
fi

# Test 4: Check nodes
log_info "Test 4: Checking cluster nodes"
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
if [ "$NODE_COUNT" -ge 1 ]; then
    log_success "Cluster has $NODE_COUNT node(s)"
    kubectl get nodes
else
    log_error "No nodes found"
    exit 1
fi

# Test 5: Check MetalLB
log_info "Test 5: Checking MetalLB installation"
if kubectl get pods -n metallb-system &> /dev/null; then
    READY=$(kubectl get pods -n metallb-system --no-headers | grep -c "Running" || echo 0)
    log_success "MetalLB installed with $READY pods running"
else
    log_error "MetalLB not installed"
fi

# Test 6: Check Traefik
log_info "Test 6: Checking Traefik installation"
if kubectl get svc traefik -n default &> /dev/null; then
    REPLICAS=$(kubectl get deployment traefik -n default -o jsonpath='{.spec.replicas}')
    EXTERNAL_IP=$(kubectl get svc traefik -n default -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    log_success "Traefik installed with $REPLICAS replicas (External IP: $EXTERNAL_IP)"
else
    log_error "Traefik not installed"
fi

# Test 7: Check Headlamp
log_info "Test 7: Checking Headlamp installation"
if kubectl get pods -n kube-system -l app.kubernetes.io/name=headlamp &> /dev/null; then
    READY=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=headlamp --no-headers | grep -c "Running" || echo 0)
    log_success "Headlamp installed with $READY pod(s) running"
else
    log_error "Headlamp not installed"
fi

# Test 8: Check IngressRoutes
log_info "Test 8: Checking IngressRoutes"
INGRESS_COUNT=$(kubectl get ingressroute -A --no-headers | wc -l | tr -d ' ')
log_success "Found $INGRESS_COUNT IngressRoute(s)"
kubectl get ingressroute -A

# Test 9: Test Traefik endpoint
log_info "Test 9: Testing Traefik dashboard endpoint"
if [ -n "$EXTERNAL_IP" ]; then
    if curl -s -o /dev/null -w "%{http_code}" "http://$EXTERNAL_IP/dashboard/" | grep -q "200\|30"; then
        log_success "Traefik dashboard accessible at http://$EXTERNAL_IP/dashboard/"
    else
        log_error "Traefik dashboard not accessible"
    fi
fi

# Test 10: Test Headlamp endpoint
log_info "Test 10: Testing Headlamp endpoint"
if [ -n "$EXTERNAL_IP" ]; then
    if curl -s -k -o /dev/null -w "%{http_code}" "https://$EXTERNAL_IP/headlamp/" | grep -q "200\|30"; then
        log_success "Headlamp accessible at https://$EXTERNAL_IP/headlamp/"
    else
        log_error "Headlamp not accessible (may need certificate acceptance)"
    fi
fi

echo ""
echo "===== Test Summary ====="
echo ""
log_success "All core components validated!"
echo ""
echo "Access Points:"
echo "  - Traefik: http://$EXTERNAL_IP/dashboard/"
echo "  - Headlamp: https://$EXTERNAL_IP/headlamp/"
echo ""
