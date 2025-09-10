# PyTorch Migration Quick Reference

## 🚀 30-Second Conversion

### API Changes
```yaml
# FROM (PyTorchJob v1)
apiVersion: kubeflow.org/v1
kind: PyTorchJob

# TO (TrainJob v2)
apiVersion: trainer.kubeflow.org/v1alpha1
kind: TrainJob
```

### Runtime Reference
```yaml
spec:
  runtimeRef:
    name: torch-distributed  # CPU training
    # OR
    name: torch-cuda-251     # GPU training
```

### Node Count Calculation
```yaml
# v1: Master + Workers
pytorchReplicaSpecs:
  Master: {replicas: 1}
  Worker: {replicas: 3}

# v2: Total nodes
trainer:
  numNodes: 4  # 1 + 3 = 4
```

### Container Configuration
```yaml
# v1: Duplicated specs
Master:
  template:
    spec:
      containers:
        - name: pytorch
          image: my-image
          command: ["python", "train.py"]
          resources: {...}
Worker:
  template:
    spec:
      containers:
        - name: pytorch
          image: my-image
          command: ["python", "train.py"]
          resources: {...}

# v2: Single spec
trainer:
  image: my-image
  command: ["python", "train.py"]
  resourcesPerNode: {...}  # Applied to all nodes
```

## 📊 Common Patterns

| Scenario | v1 Configuration | v2 Configuration |
|----------|------------------|------------------|
| **Single Node** | `Master: {replicas: 1}` | `numNodes: 1` |
| **Distributed** | `Master: {replicas: 1}, Worker: {replicas: 3}` | `numNodes: 4` |
| **CPU Training** | Any PyTorchJob | `runtimeRef: {name: torch-distributed}` |
| **GPU Training** | Resources with `nvidia.com/gpu` | `runtimeRef: {name: torch-cuda-251}` |

## ⚡ Conversion Commands

```bash
# Single file
python3 tools/convert-pytorch.py input.yaml output.yaml

# Directory batch conversion
python3 tools/convert-pytorch.py --directory ./pytorch-jobs --output-dir ./trainjobs

# Validation
./tools/validate-readiness.sh
```

## 🔧 Runtime Selection

| Use Case | Runtime Name | Notes |
|----------|--------------|-------|
| CPU Training | `torch-distributed` | Default PyTorch distributed |
| GPU CUDA 12.4 | `torch-cuda-241` | CUDA 12.4 optimized |
| GPU CUDA 12.5 | `torch-cuda-251` | Latest CUDA support |
| DeepSpeed | `deepspeed-distributed` | For DeepSpeed workloads |

## ❗ Common Gotchas

1. **Resource Field**: Use `resourcesPerNode` not `resources`
2. **Node Count**: Sum all replica counts from v1
3. **Runtime Required**: Must exist before deploying TrainJob
4. **Unified Resources**: v2 applies same resources to all nodes

## 🆘 Quick Fixes

### "unknown field spec.trainer.resources"
```yaml
# ❌ Wrong
trainer:
  resources: {...}

# ✅ Correct  
trainer:
  resourcesPerNode: {...}
```

### "ClusterTrainingRuntime not found"
```bash
kubectl apply -k {path_to_trainer}/trainer/manifests/rhoai/runtimes --server-side=true
```

### Different resources per node
```yaml
# v1 had different Master vs Worker resources
# v2 solution: Use maximum resources for all nodes
trainer:
  resourcesPerNode:
    limits:
      cpu: 8        # Use higher limit
      memory: 16Gi
```

## 📋 Migration Checklist

### Pre-Migration
- [ ] Run `./tools/validate-readiness.sh`
- [ ] Backup PyTorchJobs: `kubectl get pytorchjobs --all-namespaces -o yaml > backup.yaml`
- [ ] Test conversion: `python3 tools/convert-pytorch.py test-job.yaml test-job-v2.yaml`

### During Migration
- [ ] Deploy v2 with different name: `sed 's/name: job/name: job-v2/' job-v2.yaml | kubectl apply -f -`
- [ ] Compare logs: `kubectl logs job-master-0` vs `kubectl logs job-v2-node-0-0-xxxxx`
- [ ] Validate training metrics match

### Post-Migration
- [ ] All TrainJobs running: `kubectl get trainjobs --all-namespaces`
- [ ] Update CI/CD pipelines
- [ ] Remove old PyTorchJobs: `kubectl delete pytorchjobs --all`

## 🔍 Validation Commands

```bash
# Check operator status
kubectl get deployment -n opendatahub | grep -E "(training-operator|trainer-controller)"

# List available runtimes
kubectl get clustertrainingruntime

# Monitor job status
kubectl get trainjobs --all-namespaces -w

# Check training logs
kubectl logs -l trainer.kubeflow.org/trainjob-name=my-job --tail=20

# Compare performance
kubectl top pods | grep trainjob
```

## 📞 Help Resources

- **Environment Issues**: `./tools/validate-readiness.sh`
- **Conversion Issues**: Check [examples/pytorch-examples/](../examples/pytorch-examples/)
- **Runtime Issues**: `kubectl describe clustertrainingruntime torch-distributed`
- **Complex Scenarios**: See [Complete Guide](COMPLETE_MIGRATION_GUIDE.md)

---

*Keep this reference handy during your PyTorch migration!*
