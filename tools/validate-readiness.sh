#!/bin/bash
# Migration Readiness Validation Script
# 
# This script checks if your Red Hat AI environment is ready for 
# Kubeflow Training Operator v1 to Trainer v2 migration.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check kubectl access
check_kubectl() {
    log_info "Checking kubectl access..."
    
    if ! command_exists kubectl; then
        log_error "kubectl not found. Please install kubectl."
        return 1
    fi
    
    if ! kubectl auth can-i get pods >/dev/null 2>&1; then
        log_error "kubectl not properly configured or insufficient permissions."
        return 1
    fi
    
    log_success "kubectl is properly configured"
    return 0
}

# Check Training Operator v1 status
check_training_operator_v1() {
    log_info "Checking Training Operator v1 status..."
    
    # Check for v1 deployment
    if kubectl get deployment -n opendatahub kubeflow-training-operator >/dev/null 2>&1; then
        local status=$(kubectl get deployment -n opendatahub kubeflow-training-operator -o jsonpath='{.status.readyReplicas}/{.status.replicas}')
        log_success "Training Operator v1 found: $status ready"
    else
        log_warning "Training Operator v1 not found in opendatahub namespace"
        log_info "Checking other namespaces..."
        
        local found_namespaces=$(kubectl get deployment --all-namespaces -o jsonpath='{range .items[?(@.metadata.name=="kubeflow-training-operator")]}{.metadata.namespace}{"\n"}{end}')
        
        if [ -n "$found_namespaces" ]; then
            log_success "Training Operator v1 found in: $found_namespaces"
        else
            log_error "Training Operator v1 not found in any namespace"
            return 1
        fi
    fi
    
    # Check v1 CRDs
    local v1_crds=("pytorchjobs.kubeflow.org" "tfjobs.kubeflow.org" "mpijobs.kubeflow.org")
    local missing_crds=()
    
    for crd in "${v1_crds[@]}"; do
        if kubectl get crd "$crd" >/dev/null 2>&1; then
            log_success "CRD found: $crd"
        else
            missing_crds+=("$crd")
        fi
    done
    
    if [ ${#missing_crds[@]} -gt 0 ]; then
        log_warning "Missing v1 CRDs: ${missing_crds[*]}"
    fi
    
    return 0
}

# Check existing PyTorchJobs
check_existing_jobs() {
    log_info "Checking existing PyTorchJobs..."
    
    local total_jobs=0
    local namespaces_with_jobs=()
    
    # Get all namespaces with PyTorchJobs
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            local namespace=$(echo "$line" | awk '{print $1}')
            local count=$(echo "$line" | awk '{print $2}')
            namespaces_with_jobs+=("$namespace:$count")
            total_jobs=$((total_jobs + count))
        fi
    done < <(kubectl get pytorchjobs --all-namespaces --no-headers 2>/dev/null | awk '{print $1}' | sort | uniq -c | awk '{print $2, $1}')
    
    if [ $total_jobs -eq 0 ]; then
        log_info "No existing PyTorchJobs found"
    else
        log_success "Found $total_jobs PyTorchJobs across ${#namespaces_with_jobs[@]} namespaces:"
        for namespace_info in "${namespaces_with_jobs[@]}"; do
            local ns=$(echo "$namespace_info" | cut -d':' -f1)
            local count=$(echo "$namespace_info" | cut -d':' -f2)
            echo "  - $ns: $count jobs"
        done
    fi
    
    return 0
}

# Check Trainer v2 status
check_trainer_v2() {
    log_info "Checking Kubeflow Trainer v2 status..."
    
    # Check for v2 CRDs
    local v2_crds=("trainjobs.trainer.kubeflow.org" "clustertrainingruntimes.trainer.kubeflow.org" "trainingruntimes.trainer.kubeflow.org")
    local v2_installed=true
    
    for crd in "${v2_crds[@]}"; do
        if kubectl get crd "$crd" >/dev/null 2>&1; then
            log_success "Trainer v2 CRD found: $crd"
        else
            log_warning "Trainer v2 CRD missing: $crd"
            v2_installed=false
        fi
    done
    
    # Check for v2 deployment
    if kubectl get deployment -n opendatahub kubeflow-trainer-controller-manager >/dev/null 2>&1; then
        local status=$(kubectl get deployment -n opendatahub kubeflow-trainer-controller-manager -o jsonpath='{.status.readyReplicas}/{.status.replicas}')
        log_success "Trainer v2 controller found: $status ready"
    else
        log_warning "Trainer v2 controller not found in opendatahub namespace"
        v2_installed=false
    fi
    
    if [ "$v2_installed" = true ]; then
        log_success "Kubeflow Trainer v2 is installed"
        
        # Check available runtimes
        log_info "Available ClusterTrainingRuntimes:"
        kubectl get clustertrainingruntimes --no-headers 2>/dev/null | while read -r line; do
            local runtime_name=$(echo "$line" | awk '{print $1}')
            echo "  - $runtime_name"
        done
    else
        log_warning "Kubeflow Trainer v2 is not fully installed"
    fi
    
    return 0
}

# Check resource availability
check_resources() {
    log_info "Checking cluster resources..."
    
    # Check node count and capacity
    local node_count=$(kubectl get nodes --no-headers | wc -l)
    log_info "Cluster has $node_count nodes"
    
    # Check for GPU nodes
    local gpu_nodes=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.capacity.nvidia\.com/gpu}{"\n"}{end}' | grep -v '<no value>' | wc -l)
    if [ "$gpu_nodes" -gt 0 ]; then
        log_success "Found $gpu_nodes GPU nodes"
    else
        log_info "No GPU nodes detected (CPU-only training available)"
    fi
    
    # Check storage classes
    local storage_classes=$(kubectl get storageclass --no-headers | wc -l)
    if [ "$storage_classes" -gt 0 ]; then
        log_success "Found $storage_classes storage classes"
    else
        log_warning "No storage classes found"
    fi
    
    return 0
}

# Check permissions
check_permissions() {
    log_info "Checking required permissions..."
    
    local required_permissions=(
        "get pods"
        "create trainjobs"
        "get trainjobs"
        "delete pytorchjobs"
        "get clustertrainingruntimes"
    )
    
    local permission_issues=()
    
    for permission in "${required_permissions[@]}"; do
        if kubectl auth can-i $permission >/dev/null 2>&1; then
            log_success "Permission OK: $permission"
        else
            permission_issues+=("$permission")
        fi
    done
    
    if [ ${#permission_issues[@]} -gt 0 ]; then
        log_warning "Missing permissions: ${permission_issues[*]}"
        log_info "You may need cluster-admin or specific RBAC permissions"
    fi
    
    return 0
}

# Generate migration recommendations
generate_recommendations() {
    log_info "Generating migration recommendations..."
    echo ""
    echo "=== MIGRATION READINESS REPORT ==="
    echo ""
    
    # Check if both v1 and v2 are available
    local v1_ready=false
    local v2_ready=false
    
    if kubectl get deployment -n opendatahub kubeflow-training-operator >/dev/null 2>&1; then
        v1_ready=true
    fi
    
    if kubectl get crd trainjobs.trainer.kubeflow.org >/dev/null 2>&1 && \
       kubectl get deployment -n opendatahub kubeflow-trainer-controller-manager >/dev/null 2>&1; then
        v2_ready=true
    fi
    
    if [ "$v1_ready" = true ] && [ "$v2_ready" = true ]; then
        log_success "READY: Both v1 and v2 operators are available - perfect for side-by-side migration"
        echo ""
        echo "Recommended next steps:"
        echo "1. Use conversion script: python convert-pytorchjob-to-trainjob.py"
        echo "2. Test converted jobs alongside existing v1 jobs"
        echo "3. Validate training results match between v1 and v2"
        echo "4. Gradually migrate workloads"
        
    elif [ "$v1_ready" = true ] && [ "$v2_ready" = false ]; then
        log_warning "PARTIAL: v1 operator found, v2 not installed"
        echo ""
        echo "Recommended next steps:"
        echo "1. Install Kubeflow Trainer v2:"
        echo "   kubectl apply -k {path_to_trainer}/trainer/manifests/rhoai --server-side=true"
        echo "2. Install base runtimes:"
        echo "   kubectl apply -k {path_to_trainer}/trainer/manifests/rhoai/runtimes --server-side=true"
        echo "3. Return to this validation script"
        
    elif [ "$v1_ready" = false ] && [ "$v2_ready" = true ]; then
        log_info "INFO: Only v2 operator found - ready for new TrainJob deployments"
        
    else
        log_error "BLOCKED: Neither v1 nor v2 operators found"
        echo ""
        echo "Required actions:"
        echo "1. Install Training Operator v1 OR Kubeflow Trainer v2"
        echo "2. Check Red Hat AI platform documentation"
    fi
    
    return 0
}

# Main execution
main() {
    echo "🔍 Kubeflow Training Operator v1 → Trainer v2 Migration Readiness Check"
    echo "=================================================================="
    echo ""
    
    # Run all checks
    check_kubectl || exit 1
    check_training_operator_v1
    check_existing_jobs
    check_trainer_v2
    check_resources
    check_permissions
    
    echo ""
    generate_recommendations
    
    echo ""
    echo "✅ Validation completed!"
    echo ""
    echo "For detailed migration guidance, see:"
    echo "- CUSTOMER_MIGRATION_GUIDE.md"
    echo "- MIGRATION_QUICK_REFERENCE.md"
}

# Run main function
main "$@"
