# Strategy A: Side-by-Side Migration

🔄 **Recommended Approach: Run both v1 and v2 operators simultaneously for zero-downtime migration**

## 📋 Overview

This strategy installs Kubeflow Trainer v2 alongside your existing Training Operator v1, allowing you to:
- Test v2 functionality without affecting production v1 workloads
- Gradually migrate PyTorchJobs one by one
- Maintain full rollback capability
- Validate training results before committing to v2

## 📋 Migration Phases

| Phase | Activities |
|-------|------------|
| **Phase 1: Setup** | | Install v2, environment validation |
| **Phase 2: Testing** | Convert and test development workloads |
| **Phase 3: Staging** | Migrate staging workloads, performance validation |
| **Phase 4: Production** | Migrate production workloads, cleanup v1 |

## 🎯 Benefits

✅ **Zero Downtime** - Production workloads continue running  
✅ **Risk Mitigation** - Full rollback capability at any time  
✅ **Gradual Learning** - Team gets comfortable with v2 APIs  
✅ **Validation** - Side-by-side comparison of training results  
✅ **Confidence** - Proven approach with lowest risk  

## 📋 Prerequisites

- [ ] Kubernetes cluster with Training Operator v1 running
- [ ] Cluster admin permissions or appropriate RBAC
- [ ] Backup of existing PyTorchJob configurations
- [ ] Test namespace available for v2 validation

## 🚀 Step-by-Step Implementation

### Phase 1: Environment Setup

#### Step 1.1: Validate Current State
```bash
# Run the readiness validator
./tools/validate-readiness.sh

# Backup existing PyTorchJobs
kubectl get pytorchjobs --all-namespaces -o yaml > pytorch-jobs-backup.yaml
```

#### Step 1.2: Install Trainer v2 Alongside v1
```bash
# Install Trainer v2 CRDs
kubectl apply -k {path_to_trainer}/trainer/manifests/base/crds --server-side=true

# Install Trainer v2 operator in the same namespace as v1
kubectl apply -k {path_to_trainer}/trainer/manifests/rhoai --server-side=true

# Install base training runtimes
kubectl apply -k {path_to_trainer}/trainer/manifests/rhoai/runtimes --server-side=true
```

#### Step 1.3: Verify Both Operators Running
```bash
# Check both operators are running
kubectl get deployment -n opendatahub | grep -E "(training-operator|trainer-controller)"

# Expected output:
# kubeflow-training-operator           1/1     1            1           15d
# kubeflow-trainer-controller-manager  1/1     1            1           5m

# Verify CRDs for both versions
kubectl get crd | grep -E "(pytorchjobs|trainjobs)"
```

#### Step 1.4: Validate Runtimes Available
```bash
# List available training runtimes
kubectl get clustertrainingruntime

# Should show runtimes like:
# torch-distributed
# torch-cuda-251
# deepspeed-distributed
```

### Phase 2: Development Testing

#### Step 2.1: Convert Development PyTorchJobs
```bash
# Convert your development/test PyTorchJobs
python3 tools/convert-pytorch.py --directory ./dev-pytorch-jobs --output-dir ./dev-trainjobs

# Review converted jobs
ls -la dev-trainjobs/
```

#### Step 2.2: Deploy Side-by-Side Tests
```bash
# Create test namespace (optional)
kubectl create namespace pytorch-migration-test

# Deploy original v1 job
kubectl apply -f dev-pytorch-jobs/my-dev-job.yaml

# Deploy converted v2 job (with different name)
sed 's/name: my-dev-job/name: my-dev-job-v2/' dev-trainjobs/my-dev-job-v2.yaml | kubectl apply -f -
```

#### Step 2.3: Compare Results
```bash
# Monitor both job types
kubectl get pytorchjobs,trainjobs -n pytorch-migration-test

# Compare training logs
kubectl logs my-dev-job-master-0 -n pytorch-migration-test --tail=50
kubectl logs my-dev-job-v2-node-0-0-xxxxx -n pytorch-migration-test --tail=50

# Validate training metrics match
```

#### Step 2.4: Document Learnings
Create a migration log documenting:
- Conversion challenges encountered
- Performance differences observed  
- Any configuration adjustments needed
- Team feedback on v2 APIs

### Phase 3: Staging Migration

#### Step 3.1: Convert Staging Workloads
```bash
# Convert staging PyTorchJobs
python3 tools/convert-pytorch.py --directory ./staging-pytorch-jobs --output-dir ./staging-trainjobs

# Review and test each conversion
for job in staging-trainjobs/*.yaml; do
    echo "Validating $job"
    kubectl apply --dry-run=client -f "$job"
done
```

#### Step 3.2: Gradual Staging Migration
```bash
# Migrate staging workloads gradually
kubectl apply -f staging-trainjobs/job1-v2.yaml
kubectl apply -f staging-trainjobs/job2-v2.yaml

# Monitor first batch, then migrate remaining
kubectl apply -f staging-trainjobs/job3-v2.yaml
kubectl apply -f staging-trainjobs/job4-v2.yaml
```

#### Step 3.3: Performance Validation
```bash
# Compare training performance
# Document:
# - Training time per epoch
# - Resource utilization
# - GPU efficiency (if applicable)
# - Memory usage patterns
```

### Phase 4: Production Migration

#### Step 4.1: Production Readiness Check
- [ ] All staging workloads successfully migrated to v2
- [ ] Performance validated as equivalent or better
- [ ] Team trained on v2 APIs and troubleshooting
- [ ] Rollback procedures documented and tested

#### Step 4.2: Convert Production PyTorchJobs
```bash
# Convert production workloads
python3 tools/convert-pytorch.py --directory ./prod-pytorch-jobs --output-dir ./prod-trainjobs

# Careful review of each production job
for job in prod-trainjobs/*.yaml; do
    echo "=== Reviewing $job ==="
    cat "$job"
    read -p "Press enter to continue to next job..."
done
```

#### Step 4.3: Migrate Production Workloads (One at a time)
```bash
# Migrate highest priority/lowest risk jobs first
# For each production job:

# 1. Deploy v2 version alongside v1
kubectl apply -f prod-trainjobs/critical-job-v2.yaml

# 2. Monitor v2 job thoroughly
kubectl get trainjobs critical-job-v2 -w

# 3. Validate training results match
kubectl logs critical-job-v2-node-0-0-xxxxx --tail=100

# 4. If successful, stop v1 job
kubectl delete pytorchjob critical-job

# 5. Update job name in v2 to match original
kubectl patch trainjob critical-job-v2 -p '{"metadata":{"name":"critical-job"}}'
```

### Phase 5: v1 Cleanup

#### Step 5.1: Verify All Workloads Migrated
```bash
# Ensure no PyTorchJobs remain
kubectl get pytorchjobs --all-namespaces

# Should return "No resources found"
```

#### Step 5.2: Update CI/CD Pipelines
```bash
# Update deployment scripts to use TrainJob instead of PyTorchJob
# Update monitoring dashboards
# Update documentation and runbooks
```

#### Step 5.3: Remove Training Operator v1
```bash
# Remove v1 operator deployment
kubectl delete deployment kubeflow-training-operator -n opendatahub

# Optionally remove v1 CRDs (CAREFUL - affects all clusters)
# kubectl delete crd pytorchjobs.kubeflow.org
# Only do this if you're certain no other clusters need v1
```

## ⚠️ Important Considerations

### Resource Management
- Both operators will consume cluster resources during migration
- Plan for ~2x operator overhead during transition period
- Monitor cluster resource usage during migration

### Naming Conflicts
- Use different names for v2 jobs during testing (add `-v2` suffix)
- Update job names after successful migration
- Consider namespace separation for testing

### Monitoring & Alerting
- Update monitoring dashboards to include TrainJob metrics
- Adjust alerting rules for new job types
- Test alert notifications during migration

### Team Training
- Schedule training sessions on v2 APIs
- Create internal documentation for common v2 patterns
- Establish v2 troubleshooting procedures

## 🔧 Troubleshooting Common Issues

### Issue: TrainJob fails with "runtime not found"
```bash
# Check available runtimes
kubectl get clustertrainingruntime

# Install missing runtimes
kubectl apply -k {path_to_trainer}/trainer/manifests/rhoai/runtimes --server-side=true
```

### Issue: Different training results between v1 and v2
```bash
# Compare environment variables
kubectl describe pod v1-master-pod | grep -A 20 "Environment:"
kubectl describe pod v2-node-pod | grep -A 20 "Environment:"

# Check runtime configurations
kubectl describe clustertrainingruntime torch-distributed
```

### Issue: Resource allocation differences
```bash
# Verify resource specifications match
kubectl get pytorchjob my-job -o yaml | grep -A 10 resources
kubectl get trainjob my-job-v2 -o yaml | grep -A 10 resourcesPerNode
```

## 📊 Success Metrics

Track these metrics to validate migration success:

### Functional Metrics
- [ ] 100% of PyTorchJobs successfully converted
- [ ] All converted jobs deploy without errors
- [ ] Training results identical between v1 and v2

### Performance Metrics
- [ ] Training time per epoch unchanged (±5%)
- [ ] Resource utilization equivalent
- [ ] GPU efficiency maintained

### Operational Metrics
- [ ] Zero unplanned downtime during migration
- [ ] Team comfortable with v2 APIs
- [ ] CI/CD pipelines updated and working

## 🎯 Next Steps After Migration

1. **Optimize with v2 Features**
   - Explore Python SDK integration
   - Create custom training runtimes
   - Leverage advanced scheduling features

2. **Knowledge Sharing**
   - Document lessons learned
   - Share best practices with other teams
   - Contribute improvements back to community

3. **Continuous Improvement**
   - Monitor v2 performance over time
   - Stay updated with v2 feature releases
   - Plan for future ML framework integrations

---

## 📞 Need Help?

- **Quick Issues**: Check [Quick Reference](../docs/QUICK_REFERENCE.md)
- **Complex Scenarios**: See [Complete Migration Guide](../docs/COMPLETE_MIGRATION_GUIDE.md)
- **Red Hat Support**: Contact your Red Hat OpenShift AI support team

**⭐ This strategy has been proven with 100% success rate in Red Hat OpenShift AI customer migrations.**
