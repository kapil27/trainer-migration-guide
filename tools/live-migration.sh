#!/bin/bash
# Live PyTorch Migration Script
# 
# Extract PyTorchJobs from cluster, convert to TrainJobs, and deploy them

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
Live PyTorch Migration Tool

DESCRIPTION:
    Extract PyTorchJobs from running cluster, convert to TrainJobs, and deploy them.
    Supports both individual jobs and bulk migration scenarios.

USAGE:
    $0 <command> [options]

COMMANDS:
    list                    List all PyTorchJobs in cluster
    extract                 Extract PyTorchJobs from cluster
    convert-and-deploy      Extract, convert, and deploy as TrainJobs
    migrate-namespace       Migrate all PyTorchJobs in a namespace
    migrate-job             Migrate specific PyTorchJob by name
    rollback               Rollback TrainJobs to PyTorchJobs

OPTIONS:
    --namespace, -n        Target namespace (default: current context)
    --all-namespaces       Process all namespaces
    --dry-run             Show what would be done without executing
    --backup-dir          Directory to store backups (default: ./backups)
    --force               Skip confirmations
    --suffix              Add suffix to converted job names (default: -v2)

EXAMPLES:
    # List all PyTorchJobs
    $0 list --all-namespaces
    
    # Extract PyTorchJobs from production namespace
    $0 extract --namespace production
    
    # Migrate entire namespace (side-by-side)
    $0 migrate-namespace --namespace ml-training --suffix -v2
    
    # Migrate specific job
    $0 migrate-job --namespace production --job-name bert-training
    
    # Full conversion and deployment (use with caution)
    $0 convert-and-deploy --namespace staging --dry-run
    
    # Rollback if needed
    $0 rollback --namespace staging --backup-dir ./backups

EOF
}

# List PyTorchJobs
list_pytorch_jobs() {
    local namespace="$1"
    local all_namespaces="$2"
    
    log_info "Listing PyTorchJobs in cluster..."
    
    if [[ "$all_namespaces" == "true" ]]; then
        kubectl get pytorchjobs --all-namespaces -o wide
    elif [[ -n "$namespace" ]]; then
        kubectl get pytorchjobs -n "$namespace" -o wide
    else
        kubectl get pytorchjobs -o wide
    fi
}

# Extract PyTorchJobs from cluster
extract_pytorch_jobs() {
    local namespace="$1"
    local all_namespaces="$2"
    local backup_dir="$3"
    local dry_run="$4"
    
    log_info "Extracting PyTorchJobs from cluster..."
    
    # Create backup directory
    if [[ "$dry_run" != "true" ]]; then
        mkdir -p "$backup_dir"
    fi
    
    if [[ "$all_namespaces" == "true" ]]; then
        # Get all PyTorchJobs across all namespaces
        local namespaces=$(kubectl get pytorchjobs --all-namespaces --no-headers | awk '{print $1}' | sort -u)
        
        for ns in $namespaces; do
            log_info "Extracting PyTorchJobs from namespace: $ns"
            local output_file="$backup_dir/${ns}-pytorchjobs.yaml"
            
            if [[ "$dry_run" == "true" ]]; then
                log_info "Would extract to: $output_file"
                kubectl get pytorchjobs -n "$ns" --no-headers | awk '{print $1}'
            else
                kubectl get pytorchjobs -n "$ns" -o yaml > "$output_file"
                local job_count=$(kubectl get pytorchjobs -n "$ns" --no-headers | wc -l)
                log_success "Extracted $job_count PyTorchJobs from $ns to $output_file"
            fi
        done
    elif [[ -n "$namespace" ]]; then
        # Get PyTorchJobs from specific namespace
        local output_file="$backup_dir/${namespace}-pytorchjobs.yaml"
        
        if [[ "$dry_run" == "true" ]]; then
            log_info "Would extract to: $output_file"
            kubectl get pytorchjobs -n "$namespace" --no-headers | awk '{print $1}'
        else
            kubectl get pytorchjobs -n "$namespace" -o yaml > "$output_file"
            local job_count=$(kubectl get pytorchjobs -n "$namespace" --no-headers | wc -l)
            log_success "Extracted $job_count PyTorchJobs from $namespace to $output_file"
        fi
    else
        # Get PyTorchJobs from current namespace
        local current_ns=$(kubectl config view --minify --output 'jsonpath={..namespace}')
        current_ns=${current_ns:-default}
        local output_file="$backup_dir/${current_ns}-pytorchjobs.yaml"
        
        if [[ "$dry_run" == "true" ]]; then
            log_info "Would extract to: $output_file"
            kubectl get pytorchjobs --no-headers | awk '{print $1}'
        else
            kubectl get pytorchjobs -o yaml > "$output_file"
            local job_count=$(kubectl get pytorchjobs --no-headers | wc -l)
            log_success "Extracted $job_count PyTorchJobs from $current_ns to $output_file"
        fi
    fi
}

# Convert and deploy PyTorchJobs
convert_and_deploy() {
    local namespace="$1"
    local all_namespaces="$2"
    local backup_dir="$3"
    local dry_run="$4"
    local suffix="$5"
    local force="$6"
    
    log_info "Starting convert and deploy process..."
    
    # First extract the jobs
    extract_pytorch_jobs "$namespace" "$all_namespaces" "$backup_dir" "$dry_run"
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "Dry run completed. Use without --dry-run to execute."
        return 0
    fi
    
    # Find extracted files
    local extracted_files=$(find "$backup_dir" -name "*-pytorchjobs.yaml" -type f)
    
    if [[ -z "$extracted_files" ]]; then
        log_error "No extracted PyTorchJob files found in $backup_dir"
        exit 1
    fi
    
    # Convert each file
    for file in $extracted_files; do
        local basename=$(basename "$file" -pytorchjobs.yaml)
        local converted_file="$backup_dir/${basename}-trainjobs.yaml"
        
        log_info "Converting $file to TrainJobs..."
        
        # Use the conversion script
        if python3 tools/convert-pytorch.py "$file" "$converted_file"; then
            log_success "Converted: $file → $converted_file"
        else
            log_error "Failed to convert: $file"
            continue
        fi
        
        # Deploy converted TrainJobs
        if [[ -f "$converted_file" ]]; then
            log_info "Deploying TrainJobs from $converted_file..."
            
            # Add suffix to job names if specified
            if [[ -n "$suffix" ]]; then
                sed "s/name: /name: /g; s/name: \\(.*\\)/name: \\1$suffix/" "$converted_file" > "$backup_dir/temp-${basename}-trainjobs.yaml"
                mv "$backup_dir/temp-${basename}-trainjobs.yaml" "$converted_file"
            fi
            
            # Apply the TrainJobs
            if kubectl apply -f "$converted_file"; then
                log_success "Successfully deployed TrainJobs from $converted_file"
            else
                log_error "Failed to deploy TrainJobs from $converted_file"
            fi
        fi
    done
}

# Migrate specific namespace
migrate_namespace() {
    local namespace="$1"
    local backup_dir="$2"
    local dry_run="$3"
    local suffix="$4"
    local force="$5"
    
    if [[ -z "$namespace" ]]; then
        log_error "Namespace is required for namespace migration"
        exit 1
    fi
    
    log_info "Migrating all PyTorchJobs in namespace: $namespace"
    
    # Check if namespace exists
    if ! kubectl get namespace "$namespace" > /dev/null 2>&1; then
        log_error "Namespace '$namespace' does not exist"
        exit 1
    fi
    
    # Count existing PyTorchJobs
    local job_count=$(kubectl get pytorchjobs -n "$namespace" --no-headers 2>/dev/null | wc -l)
    
    if [[ $job_count -eq 0 ]]; then
        log_info "No PyTorchJobs found in namespace: $namespace"
        return 0
    fi
    
    log_info "Found $job_count PyTorchJobs in namespace: $namespace"
    
    if [[ "$force" != "true" && "$dry_run" != "true" ]]; then
        kubectl get pytorchjobs -n "$namespace"
        echo
        read -p "Proceed with migration of these jobs? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Migration cancelled"
            exit 0
        fi
    fi
    
    # Perform the migration
    convert_and_deploy "$namespace" "false" "$backup_dir" "$dry_run" "$suffix" "$force"
}

# Migrate specific job
migrate_job() {
    local namespace="$1"
    local job_name="$2"
    local backup_dir="$3"
    local dry_run="$4"
    local suffix="$5"
    
    if [[ -z "$job_name" ]]; then
        log_error "Job name is required for job migration"
        exit 1
    fi
    
    local ns_flag=""
    if [[ -n "$namespace" ]]; then
        ns_flag="-n $namespace"
    fi
    
    log_info "Migrating PyTorchJob: $job_name"
    
    # Check if job exists
    if ! kubectl get pytorchjob "$job_name" $ns_flag > /dev/null 2>&1; then
        log_error "PyTorchJob '$job_name' not found"
        exit 1
    fi
    
    # Create backup directory
    if [[ "$dry_run" != "true" ]]; then
        mkdir -p "$backup_dir"
    fi
    
    # Extract specific job
    local job_file="$backup_dir/${job_name}-pytorchjob.yaml"
    local converted_file="$backup_dir/${job_name}-trainjob.yaml"
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "Would extract $job_name to $job_file"
        log_info "Would convert to $converted_file"
        log_info "Would deploy as ${job_name}${suffix:-}"
        return 0
    fi
    
    # Extract the job
    kubectl get pytorchjob "$job_name" $ns_flag -o yaml > "$job_file"
    log_success "Extracted PyTorchJob to: $job_file"
    
    # Convert the job
    if python3 tools/convert-pytorch.py "$job_file" "$converted_file"; then
        log_success "Converted to TrainJob: $converted_file"
    else
        log_error "Failed to convert PyTorchJob: $job_name"
        exit 1
    fi
    
    # Add suffix if specified
    if [[ -n "$suffix" ]]; then
        sed "s/name: $job_name/name: $job_name$suffix/" "$converted_file" > "$backup_dir/temp-${job_name}-trainjob.yaml"
        mv "$backup_dir/temp-${job_name}-trainjob.yaml" "$converted_file"
    fi
    
    # Deploy the TrainJob
    if kubectl apply -f "$converted_file"; then
        log_success "Successfully deployed TrainJob: ${job_name}${suffix:-}"
    else
        log_error "Failed to deploy TrainJob: ${job_name}${suffix:-}"
        exit 1
    fi
}

# Rollback TrainJobs to PyTorchJobs
rollback() {
    local namespace="$1"
    local backup_dir="$2"
    local dry_run="$3"
    local force="$4"
    
    log_warning "ROLLBACK: This will restore PyTorchJobs from backup and delete TrainJobs"
    
    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup directory not found: $backup_dir"
        exit 1
    fi
    
    # Find backup files
    local backup_files=$(find "$backup_dir" -name "*-pytorchjobs.yaml" -type f)
    
    if [[ -z "$backup_files" ]]; then
        log_error "No PyTorchJob backup files found in $backup_dir"
        exit 1
    fi
    
    log_info "Found backup files:"
    for file in $backup_files; do
        echo "  - $file"
    done
    
    if [[ "$force" != "true" && "$dry_run" != "true" ]]; then
        echo
        read -p "Proceed with rollback? This will delete TrainJobs and restore PyTorchJobs (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Rollback cancelled"
            exit 0
        fi
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "Would delete TrainJobs in namespace: ${namespace:-all}"
        log_info "Would restore PyTorchJobs from backup files"
        return 0
    fi
    
    # Delete TrainJobs
    if [[ -n "$namespace" ]]; then
        log_info "Deleting TrainJobs in namespace: $namespace"
        kubectl delete trainjobs --all -n "$namespace" || true
    else
        log_info "Deleting TrainJobs in all namespaces"
        kubectl delete trainjobs --all --all-namespaces || true
    fi
    
    # Restore PyTorchJobs
    for file in $backup_files; do
        log_info "Restoring PyTorchJobs from: $file"
        kubectl apply -f "$file"
    done
    
    log_success "Rollback completed!"
}

# Parse command line arguments
parse_args() {
    local command="$1"
    shift
    
    local namespace=""
    local all_namespaces="false"
    local dry_run="false"
    local backup_dir="./backups"
    local force="false"
    local suffix=""
    local job_name=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --namespace|-n)
                namespace="$2"
                shift 2
                ;;
            --all-namespaces)
                all_namespaces="true"
                shift
                ;;
            --dry-run)
                dry_run="true"
                shift
                ;;
            --backup-dir)
                backup_dir="$2"
                shift 2
                ;;
            --force)
                force="true"
                shift
                ;;
            --suffix)
                suffix="$2"
                shift 2
                ;;
            --job-name)
                job_name="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Execute command
    case "$command" in
        "list")
            list_pytorch_jobs "$namespace" "$all_namespaces"
            ;;
        "extract")
            extract_pytorch_jobs "$namespace" "$all_namespaces" "$backup_dir" "$dry_run"
            ;;
        "convert-and-deploy")
            convert_and_deploy "$namespace" "$all_namespaces" "$backup_dir" "$dry_run" "$suffix" "$force"
            ;;
        "migrate-namespace")
            migrate_namespace "$namespace" "$backup_dir" "$dry_run" "$suffix" "$force"
            ;;
        "migrate-job")
            migrate_job "$namespace" "$job_name" "$backup_dir" "$dry_run" "$suffix"
            ;;
        "rollback")
            rollback "$namespace" "$backup_dir" "$dry_run" "$force"
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
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
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            parse_args "$command" "$@"
            ;;
    esac
}

# Run main function
main "$@"
