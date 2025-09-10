#!/bin/bash
# PyTorch Migration Helper Script
# 
# This script automates common migration workflows for PyTorch training jobs

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

# Help function
show_help() {
    cat << EOF
PyTorch Migration Helper

USAGE:
    $0 <command> [options]

COMMANDS:
    validate        Check environment readiness for migration
    convert         Convert PyTorchJob(s) to TrainJob format
    test-deploy     Deploy converted job for side-by-side testing
    compare         Compare v1 and v2 job logs
    batch-migrate   Migrate entire directory of PyTorchJobs
    live-migrate    Extract PyTorchJobs from cluster, convert and deploy
    cleanup         Remove v1 jobs after successful migration

EXAMPLES:
    $0 validate
    $0 convert my-job.yaml
    $0 convert --directory ./pytorch-jobs
    $0 test-deploy my-job-v2.yaml
    $0 compare my-job my-job-v2
    $0 batch-migrate ./production-jobs
    $0 live-migrate --namespace production --suffix -v2
    $0 cleanup --namespace production

EOF
}

# Validate environment
validate_environment() {
    log_info "Running environment validation..."
    ./validate-readiness.sh
}

# Convert single file or directory
convert_jobs() {
    local input="$1"
    local output="$2"
    local directory_mode="$3"
    
    if [[ "$directory_mode" == "true" ]]; then
        log_info "Converting directory: $input"
        python3 convert-pytorch.py --directory "$input" --output-dir "$output"
    else
        log_info "Converting file: $input"
        python3 convert-pytorch.py "$input" "$output"
    fi
    
    log_success "Conversion completed!"
}

# Test deploy converted job
test_deploy() {
    local job_file="$1"
    local namespace="${2:-default}"
    
    log_info "Test deploying TrainJob: $job_file"
    
    # Check if file exists
    if [[ ! -f "$job_file" ]]; then
        log_error "File not found: $job_file"
        exit 1
    fi
    
    # Deploy with test prefix
    sed 's/name: /name: test-/' "$job_file" | kubectl apply -n "$namespace" -f -
    
    log_success "Test deployment completed. Check status with:"
    echo "kubectl get trainjobs -n $namespace"
}

# Compare v1 and v2 job logs
compare_jobs() {
    local v1_job="$1"
    local v2_job="$2"
    local namespace="${3:-default}"
    
    log_info "Comparing job logs: $v1_job vs $v2_job"
    
    # Get v1 logs (master pod)
    local v1_pod=$(kubectl get pods -n "$namespace" -l job-name="$v1_job" --no-headers | grep master | awk '{print $1}' | head -1)
    # Get v2 logs (any node pod)
    local v2_pod=$(kubectl get pods -n "$namespace" -l trainer.kubeflow.org/trainjob-name="$v2_job" --no-headers | awk '{print $1}' | head -1)
    
    if [[ -z "$v1_pod" ]]; then
        log_warning "No v1 pods found for job: $v1_job"
    else
        echo "=== v1 Job Logs (last 20 lines) ==="
        kubectl logs "$v1_pod" -n "$namespace" --tail=20
    fi
    
    if [[ -z "$v2_pod" ]]; then
        log_warning "No v2 pods found for job: $v2_job"
    else
        echo "=== v2 Job Logs (last 20 lines) ==="
        kubectl logs "$v2_pod" -n "$namespace" --tail=20
    fi
}

# Batch migrate directory
batch_migrate() {
    local input_dir="$1"
    local namespace="${2:-default}"
    
    log_info "Starting batch migration of directory: $input_dir"
    
    # Create output directory
    local output_dir="${input_dir}-converted"
    mkdir -p "$output_dir"
    
    # Convert all PyTorchJobs
    log_info "Converting PyTorchJobs..."
    python3 convert-pytorch.py --directory "$input_dir" --output-dir "$output_dir"
    
    # Deploy each converted job
    log_info "Deploying converted TrainJobs..."
    for job_file in "$output_dir"/*.yaml; do
        if [[ -f "$job_file" ]]; then
            local job_name=$(basename "$job_file" .yaml)
            log_info "Deploying: $job_name"
            kubectl apply -f "$job_file" -n "$namespace"
            sleep 2  # Brief pause between deployments
        fi
    done
    
    log_success "Batch migration completed!"
    log_info "Monitor progress with: kubectl get trainjobs -n $namespace"
}

# Cleanup v1 jobs
cleanup_v1() {
    local namespace="${1:-default}"
    local confirm="${2:-false}"
    
    log_warning "This will delete ALL PyTorchJobs in namespace: $namespace"
    
    if [[ "$confirm" != "true" ]]; then
        read -p "Are you sure? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled"
            exit 0
        fi
    fi
    
    # List current PyTorchJobs
    local job_count=$(kubectl get pytorchjobs -n "$namespace" --no-headers 2>/dev/null | wc -l)
    
    if [[ $job_count -eq 0 ]]; then
        log_info "No PyTorchJobs found in namespace: $namespace"
        exit 0
    fi
    
    log_info "Found $job_count PyTorchJobs to delete"
    kubectl get pytorchjobs -n "$namespace"
    
    # Delete all PyTorchJobs
    kubectl delete pytorchjobs --all -n "$namespace"
    
    log_success "Cleanup completed!"
}

# Main script logic
main() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 1
    fi
    
    local command="$1"
    shift
    
    case "$command" in
        "validate")
            validate_environment
            ;;
        "convert")
            if [[ "$1" == "--directory" ]]; then
                convert_jobs "$2" "${2}-converted" "true"
            else
                local input="$1"
                local output="$2"
                if [[ -z "$output" ]]; then
                    output="${input%.*}-v2.yaml"
                fi
                convert_jobs "$input" "$output" "false"
            fi
            ;;
        "test-deploy")
            test_deploy "$@"
            ;;
        "compare")
            compare_jobs "$@"
            ;;
        "batch-migrate")
            batch_migrate "$@"
            ;;
        "live-migrate")
            log_info "Delegating to live-migration.sh..."
            exec ./tools/live-migration.sh migrate-namespace "$@"
            ;;
        "cleanup")
            if [[ "$1" == "--namespace" ]]; then
                cleanup_v1 "$2" "$3"
            else
                cleanup_v1 "default" "$1"
            fi
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
