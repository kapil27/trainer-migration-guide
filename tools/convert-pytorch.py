#!/usr/bin/env python3
"""
PyTorchJob to TrainJob Converter

This script helps customers convert Kubeflow Training Operator v1 PyTorchJob
configurations to Kubeflow Trainer v2 TrainJob format.

Usage:
    python convert-pytorchjob-to-trainjob.py input.yaml output.yaml
    python convert-pytorchjob-to-trainjob.py --directory v1-jobs/ --output-dir v2-jobs/
"""

import yaml
import argparse
import os
import sys
from pathlib import Path


def calculate_num_nodes(pytorch_replica_specs):
    """Calculate total number of nodes from Master and Worker replicas."""
    master_replicas = pytorch_replica_specs.get('Master', {}).get('replicas', 0)
    worker_replicas = pytorch_replica_specs.get('Worker', {}).get('replicas', 0)
    return master_replicas + worker_replicas


def extract_container_spec(pytorch_replica_specs):
    """Extract container specification from Master or Worker."""
    # Prefer Master spec, fallback to Worker
    for role in ['Master', 'Worker']:
        if role in pytorch_replica_specs:
            containers = pytorch_replica_specs[role]['template']['spec'].get('containers', [])
            if containers:
                return containers[0]
    return None


def determine_runtime(container_spec):
    """Determine appropriate runtime based on container resources."""
    if not container_spec:
        return 'torch-distributed'
    
    resources = container_spec.get('resources', {})
    limits = resources.get('limits', {})
    requests = resources.get('requests', {})
    
    # Check for GPU
    gpu_limit = limits.get('nvidia.com/gpu') or requests.get('nvidia.com/gpu')
    if gpu_limit:
        return 'torch-cuda-251'  # Default to latest CUDA runtime
    
    return 'torch-distributed'


def extract_resources(container_spec):
    """Extract resource specification from container."""
    if not container_spec:
        return None
    return container_spec.get('resources')


def extract_env_vars(container_spec):
    """Extract environment variables from container."""
    if not container_spec:
        return None
    return container_spec.get('env')


def convert_pytorchjob_to_trainjob(pytorchjob_yaml):
    """Convert a PyTorchJob YAML to TrainJob format."""
    
    if pytorchjob_yaml.get('kind') != 'PyTorchJob':
        raise ValueError(f"Expected PyTorchJob, got {pytorchjob_yaml.get('kind')}")
    
    # Extract components from v1 PyTorchJob
    metadata = pytorchjob_yaml['metadata'].copy()
    pytorch_spec = pytorchjob_yaml['spec']
    pytorch_replica_specs = pytorch_spec['pytorchReplicaSpecs']
    
    # Calculate number of nodes
    num_nodes = calculate_num_nodes(pytorch_replica_specs)
    
    # Extract container specification
    container_spec = extract_container_spec(pytorch_replica_specs)
    if not container_spec:
        raise ValueError("No container specification found in PyTorchJob")
    
    # Determine runtime
    runtime_name = determine_runtime(container_spec)
    
    # Build TrainJob
    trainjob = {
        'apiVersion': 'trainer.kubeflow.org/v1alpha1',
        'kind': 'TrainJob',
        'metadata': metadata,
        'spec': {
            'runtimeRef': {
                'name': runtime_name
            },
            'trainer': {
                'numNodes': num_nodes,
                'image': container_spec['image']
            }
        }
    }
    
    # Add optional fields if present
    trainer_spec = trainjob['spec']['trainer']
    
    if 'command' in container_spec:
        trainer_spec['command'] = container_spec['command']
    
    if 'args' in container_spec:
        trainer_spec['args'] = container_spec['args']
    
    env_vars = extract_env_vars(container_spec)
    if env_vars:
        trainer_spec['env'] = env_vars
    
    resources = extract_resources(container_spec)
    if resources:
        trainer_spec['resourcesPerNode'] = resources
    
    # Handle elastic policy (note: requires custom runtime)
    if 'elasticPolicy' in pytorch_spec:
        print("WARNING: Elastic training detected. This requires custom runtime configuration.")
        print("         Consider using custom ClusterTrainingRuntime or contact support.")
        # Add as annotation for reference
        if 'annotations' not in trainjob['metadata']:
            trainjob['metadata']['annotations'] = {}
        trainjob['metadata']['annotations']['migration.trainer.kubeflow.org/original-elastic'] = 'true'
    
    return trainjob


def convert_file(input_file, output_file):
    """Convert a single PyTorchJob file to TrainJob format."""
    
    try:
        with open(input_file, 'r') as f:
            docs = list(yaml.safe_load_all(f))
        
        converted_docs = []
        
        for doc in docs:
            if doc and doc.get('kind') == 'PyTorchJob':
                print(f"Converting PyTorchJob: {doc['metadata']['name']}")
                converted = convert_pytorchjob_to_trainjob(doc)
                converted_docs.append(converted)
                
                # Print conversion summary
                original_master = doc['spec']['pytorchReplicaSpecs'].get('Master', {}).get('replicas', 0)
                original_worker = doc['spec']['pytorchReplicaSpecs'].get('Worker', {}).get('replicas', 0)
                new_nodes = converted['spec']['trainer']['numNodes']
                runtime = converted['spec']['runtimeRef']['name']
                
                print(f"  Master: {original_master}, Worker: {original_worker} → numNodes: {new_nodes}")
                print(f"  Runtime: {runtime}")
                
            else:
                print(f"Skipping non-PyTorchJob: {doc.get('kind', 'Unknown')}")
                converted_docs.append(doc)
        
        with open(output_file, 'w') as f:
            yaml.dump_all(converted_docs, f, default_flow_style=False)
        
        print(f"✅ Converted: {input_file} → {output_file}")
        
    except Exception as e:
        print(f"❌ Error converting {input_file}: {e}")
        return False
    
    return True


def main():
    parser = argparse.ArgumentParser(description='Convert PyTorchJob to TrainJob')
    parser.add_argument('input', nargs='?', help='Input PyTorchJob YAML file')
    parser.add_argument('output', nargs='?', help='Output TrainJob YAML file')
    parser.add_argument('--directory', '-d', help='Directory containing PyTorchJob files')
    parser.add_argument('--output-dir', '-o', help='Output directory for converted files')
    parser.add_argument('--dry-run', action='store_true', help='Show conversion without writing files')
    
    args = parser.parse_args()
    
    if args.directory:
        # Batch conversion mode
        input_dir = Path(args.directory)
        output_dir = Path(args.output_dir) if args.output_dir else input_dir / 'converted'
        
        if not input_dir.exists():
            print(f"❌ Input directory does not exist: {input_dir}")
            sys.exit(1)
        
        output_dir.mkdir(exist_ok=True)
        
        yaml_files = list(input_dir.glob('*.yaml')) + list(input_dir.glob('*.yml'))
        
        if not yaml_files:
            print(f"❌ No YAML files found in {input_dir}")
            sys.exit(1)
        
        print(f"Found {len(yaml_files)} YAML files to process...")
        
        success_count = 0
        for yaml_file in yaml_files:
            output_file = output_dir / f"{yaml_file.stem}-v2{yaml_file.suffix}"
            
            if args.dry_run:
                print(f"Would convert: {yaml_file} → {output_file}")
                continue
            
            if convert_file(yaml_file, output_file):
                success_count += 1
        
        if not args.dry_run:
            print(f"\n✅ Successfully converted {success_count}/{len(yaml_files)} files")
            print(f"📁 Output directory: {output_dir}")
    
    elif args.input and args.output:
        # Single file conversion mode
        if not os.path.exists(args.input):
            print(f"❌ Input file does not exist: {args.input}")
            sys.exit(1)
        
        if args.dry_run:
            print(f"Would convert: {args.input} → {args.output}")
            sys.exit(0)
        
        if convert_file(args.input, args.output):
            print("\n✅ Conversion completed successfully!")
        else:
            sys.exit(1)
    
    else:
        print("❌ Please provide either:")
        print("   - Single file: python convert.py input.yaml output.yaml")
        print("   - Directory: python convert.py --directory ./v1-jobs --output-dir ./v2-jobs")
        parser.print_help()
        sys.exit(1)


if __name__ == '__main__':
    main()
