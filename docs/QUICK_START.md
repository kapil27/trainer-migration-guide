# ⚡ Quick Start Guide - PyTorch Migration

**Get started with PyTorchJob → TrainJob migration in quickly**

## 🎯 What You'll Accomplish

- ✅ Validate your environment for migration
- ✅ Convert your first PyTorchJob to TrainJob format  
- ✅ Deploy and test the converted job
- ✅ Choose your migration strategy

## ⏱️ Time Required: quickly

## 🚀 Step 1: Validate Environment (quickly)

```bash
# Download and run the environment validator
./tools/validate-readiness.sh
```

**Expected Output:**
```
✅ READY: Both v1 and v2 operators are available - perfect for side-by-side migration
```

**If not ready:**
- Missing v1: Install Training Operator v1 first
- Missing v2: Run Strategy A Phase 1 setup steps

## 🔄 Step 2: Convert Your First Job (quickly)

### Find an Existing PyTorchJob
```bash
# List your current PyTorchJobs
kubectl get pytorchjobs --all-namespaces

# Export one for testing
kubectl get pytorchjob YOUR_JOB_NAME -n YOUR_NAMESPACE -o yaml > my-first-job.yaml
```

### Convert to TrainJob
```bash
# Use the conversion tool
python3 tools/convert-pytorch.py my-first-job.yaml my-first-job-v2.yaml

# Review the conversion
cat my-first-job-v2.yaml
```

**Example Conversion:**
```yaml
# Original PyTorchJob (v1)
apiVersion: kubeflow.org/v1
kind: PyTorchJob
spec:
  pytorchReplicaSpecs:
    Master:
      replicas: 1
    Worker:
      replicas: 2

# Converted TrainJob (v2)  
apiVersion: trainer.kubeflow.org/v1alpha1
kind: TrainJob
spec:
  runtimeRef:
    name: torch-distributed
  trainer:
    numNodes: 3  # 1 master + 2 workers
```

## 🧪 Step 3: Test the Converted Job (quickly)

### Deploy Side-by-Side
```bash
# Deploy original (if not already running)
kubectl apply -f my-first-job.yaml

# Deploy converted with different name
sed 's/name: YOUR_JOB_NAME/name: YOUR_JOB_NAME-v2/' my-first-job-v2.yaml | kubectl apply -f -
```

### Compare Results
```bash
# Check both jobs are running
kubectl get pytorchjobs,trainjobs -n YOUR_NAMESPACE

# Compare training logs
kubectl logs YOUR_JOB_NAME-master-0 -n YOUR_NAMESPACE --tail=10
kubectl logs YOUR_JOB_NAME-v2-node-0-0-xxxxx -n YOUR_NAMESPACE --tail=10
```

**Success Indicators:**
- ✅ Both jobs show "Running" status
- ✅ Training logs show similar progress
- ✅ Loss/accuracy trends match between v1 and v2

## 🎯 Step 4: Choose Your Strategy (quickly)

Based on your needs, pick a migration approach:

### 🔄 Strategy A: Side-by-Side (Recommended)
**Choose if you want:**
- Zero downtime migration
- Gradual team learning
- Full rollback capability
- 4-6 week timeline

👉 **[Follow Strategy A Guide](../migration-strategies/STRATEGY_A_SIDE_BY_SIDE.md)**

### ⚡ Strategy B: Complete Replacement  
**Choose if you want:**
- Fastest migration (2-3 duration)
- Clean environment without operator conflicts
- Can tolerate maintenance window

👉 **[Follow Strategy B Guide](../migration-strategies/STRATEGY_B_COMPLETE_REPLACEMENT.md)**

## 🎉 Success! What's Next?

You've successfully:
✅ Validated your environment  
✅ Converted and tested your first PyTorchJob  
✅ Chosen your migration strategy  

### Immediate Next Steps:
1. **Follow your chosen strategy guide** for complete migration
2. **Convert more jobs** using the batch conversion tool
3. **Train your team** on TrainJob APIs

### Live Migration from Cluster (Bonus)
```bash
# Extract PyTorchJobs directly from cluster and convert
./tools/live-migration.sh list --all-namespaces

# Migrate specific job with side-by-side approach
./tools/live-migration.sh migrate-job --namespace my-namespace --job-name my-pytorch-job --suffix -v2

# Migrate entire namespace (use with caution)
./tools/live-migration.sh migrate-namespace --namespace staging --suffix -v2 --dry-run
```

### Batch Conversion (Alternative)
```bash
# Convert all jobs in a directory
python3 tools/convert-pytorch.py --directory ./all-pytorch-jobs --output-dir ./all-trainjobs

# Review all conversions
ls -la all-trainjobs/
```

## 🆘 Quick Troubleshooting

### "ClusterTrainingRuntime not found"
```bash
# Install missing runtimes
kubectl apply -k {path_to_trainer}/trainer/manifests/rhoai/runtimes --server-side=true
```

### "Unknown field resourcesPerNode"  
```bash
# Check conversion tool output
python3 tools/convert-pytorch.py --help

# Ensure you're using resourcesPerNode, not resources
```

### Different Training Results
```bash
# Compare environment variables
kubectl describe pod v1-master-pod | grep -A 20 "Environment:"
kubectl describe pod v2-node-pod | grep -A 20 "Environment:"
```

## 📚 Additional Resources

- **[Complete Migration Guide](COMPLETE_MIGRATION_GUIDE.md)** - Comprehensive instructions
- **[Quick Reference](QUICK_REFERENCE.md)** - Conversion cheat sheet
- **[FAQ](FAQ.md)** - Common questions and answers
- **[Examples](../examples/pytorch-examples/)** - More conversion examples

## 🎯 Success Criteria

You'll know you're ready for full migration when:
- [x] Environment validator shows "READY" status
- [x] First converted job runs successfully
- [x] Training logs match between v1 and v2
- [x] Team understands the conversion process

---

**🚀 Ready for full migration?** Choose your strategy and follow the detailed guide!

**❓ Questions?** Check the [FAQ](FAQ.md) or contact Red Hat OpenShift AI support.
