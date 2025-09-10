# Strategy B: Complete Replacement Migration

⚡ **Fast Track Approach: Complete removal of v1 and fresh installation of v2**

## 📋 Overview

This strategy completely removes Training Operator v1 and performs a clean installation of Kubeflow Trainer v2. This approach is suitable when:
- You need to migrate quickly (faster approach)
- You can tolerate a brief maintenance window
- You have strong confidence in the conversion process
- You want to avoid resource overhead of running both operators

## 📋 Migration Phases

| Phase | Activities |
|-------|------------|
| **Phase 1: Preparation** | Backup, convert, test converted jobs |
| **Phase 2: Cutover** | Remove v1, install v2, deploy converted jobs |
| **Phase 3: Validation** | Validate, optimize, team training |

## 🎯 Benefits

⚡ **Faster Migration** - Complete in faster approach vs traditional approach  
🧹 **Clean Environment** - No operator conflicts or resource overhead  
🎯 **Focused Transition** - Team learns v2 APIs immediately  
💰 **Resource Efficient** - No duplicate operator overhead  
🚀 **Latest Features** - Immediate access to all v2 capabilities  

## ⚠️ Considerations

🛑 **Maintenance Window** - Requires downtime for cutover  
🔄 **No Rollback** - Must restore from backup if issues arise  
📈 **Higher Risk** - Less gradual validation of conversions  
👥 **Team Impact** - Immediate change to all workflows  

## 📋 Prerequisites

- [ ] Maintenance window scheduled (recommended)
- [ ] Complete backup of all PyTorchJob configurations
- [ ] Test environment available for conversion validation
- [ ] Team trained on TrainJob APIs
- [ ] Rollback plan documented

## 🚀 Step-by-Step Implementation

### Phase 1: Preparation

#### Step 1.1: Complete Environment Assessment
```bash
# Run comprehensive readiness check
./tools/validate-readiness.sh

# Document current state
kubectl get pytorchjobs --all-namespaces -o yaml > complete-pytorch-backup.yaml
kubectl get deployment -n opendatahub > operators-backup.txt
kubectl get crd | grep kubeflow > crds-backup.txt
```

#### Step 1.2: Convert ALL PyTorchJobs
```bash
# Create conversion workspace
mkdir -p conversion-workspace/original conversion-workspace/converted

# Export all existing PyTorchJobs by namespace
for ns in $(kubectl get pytorchjobs --all-namespaces --no-headers | awk '{print $1}' | sort -u); do
    kubectl get pytorchjobs -n $ns -o yaml > conversion-workspace/original/${ns}-pytorch-jobs.yaml
done

# Convert all jobs
for file in conversion-workspace/original/*.yaml; do
    basename=$(basename "$file" .yaml)
    python3 tools/convert-pytorch.py "$file" "conversion-workspace/converted/${basename}-trainjobs.yaml"
done
```

#### Step 1.3: Comprehensive Testing in Isolated Environment
```bash
# Create test namespace
kubectl create namespace pytorch-replacement-test

# Test each converted job
for job in conversion-workspace/converted/*.yaml; do
    echo "Testing $job"
    
    # Deploy with test prefix
    sed 's/name: /name: test-/' "$job" | kubectl apply -n pytorch-replacement-test -f -
    
    # Wait for job to start
    sleep 30
    
    # Check status
    kubectl get trainjobs -n pytorch-replacement-test
    
    # Collect logs for validation
    kubectl logs -n pytorch-replacement-test -l trainer.kubeflow.org/trainjob-name --tail=20
done
```

#### Step 1.4: Performance Baseline Establishment
```bash
# Document current v1 performance metrics
# - Training time per epoch for each job type
# - Resource utilization patterns
# - GPU efficiency metrics
# - Memory consumption patterns

# Create performance baseline document
echo "=== v1 Performance Baseline ===" > performance-baseline.txt
kubectl top pods -n production-namespace >> performance-baseline.txt
```

#### Step 1.5: Rollback Plan Preparation
```bash
# Create rollback artifacts
mkdir -p rollback-plan

# Export v1 operator configuration
kubectl get deployment kubeflow-training-operator -n opendatahub -o yaml > rollback-plan/v1-operator.yaml
kubectl get configmap -n opendatahub -l app=kubeflow-training-operator -o yaml > rollback-plan/v1-configmaps.yaml
kubectl get secret -n opendatahub -l app=kubeflow-training-operator -o yaml > rollback-plan/v1-secrets.yaml

# Create rollback script
cat > rollback-plan/rollback-to-v1.sh << 'EOF'
#!/bin/bash
echo "EMERGENCY ROLLBACK TO v1"
echo "1. Removing Trainer v2..."
kubectl delete deployment kubeflow-trainer-controller-manager -n opendatahub
kubectl delete crd trainjobs.trainer.kubeflow.org
kubectl delete crd clustertrainingruntimes.trainer.kubeflow.org

echo "2. Restoring Training Operator v1..."
kubectl apply -f v1-operator.yaml
kubectl apply -f v1-configmaps.yaml
kubectl apply -f v1-secrets.yaml

echo "3. Restoring PyTorchJobs..."
kubectl apply -f ../complete-pytorch-backup.yaml

echo "Rollback completed. Verify with: kubectl get pytorchjobs --all-namespaces"
EOF

chmod +x rollback-plan/rollback-to-v1.sh
```

### Phase 2: Cutover (Maintenance Window)

#### Step 2.1: Maintenance Window Start
```bash
# Announce maintenance start
echo "MAINTENANCE WINDOW STARTED: $(date)"

# Gracefully stop all running PyTorchJobs
kubectl get pytorchjobs --all-namespaces --no-headers | while read ns name rest; do
    echo "Stopping PyTorchJob $name in namespace $ns"
    kubectl delete pytorchjob $name -n $ns --wait=true
done
```

#### Step 2.2: Complete v1 Removal
```bash
# Remove Training Operator v1
kubectl delete deployment kubeflow-training-operator -n opendatahub

# Remove v1 webhook configurations
kubectl delete validatingwebhookconfiguration kubeflow-validator.training-operator.kubeflow.org

# Remove v1 RBAC (optional, can be left for safety)
# kubectl delete clusterrole kubeflow-training-operator
# kubectl delete clusterrolebinding kubeflow-training-operator

# Remove v1 CRDs (CAREFUL - this affects all clusters)
kubectl delete crd pytorchjobs.kubeflow.org
kubectl delete crd tfjobs.kubeflow.org
kubectl delete crd mpijobs.kubeflow.org
kubectl delete crd jaxjobs.kubeflow.org
kubectl delete crd paddlejobs.kubeflow.org
kubectl delete crd xgboostjobs.kubeflow.org

echo "v1 removal completed at: $(date)"
```

#### Step 2.3: Install Trainer v2
```bash
# Install Trainer v2 CRDs
kubectl apply -k https://github.com/kubeflow/trainer/manifests/base/crds --server-side=true

# Install Trainer v2 operator
kubectl apply -k https://github.com/kubeflow/trainer/manifests/rhoai --server-side=true

# Install training runtimes
kubectl apply -k https://github.com/kubeflow/trainer/manifests/base/runtimes --server-side=true

# Verify installation
kubectl get deployment -n opendatahub kubeflow-trainer-controller-manager
kubectl get crd | grep trainer.kubeflow.org
kubectl get clustertrainingruntime

echo "v2 installation completed at: $(date)"
```

#### Step 2.4: Deploy All Converted TrainJobs
```bash
# Deploy all converted jobs
for job in conversion-workspace/converted/*.yaml; do
    echo "Deploying $job"
    kubectl apply -f "$job"
    
    # Brief pause to avoid overwhelming the cluster
    sleep 5
done

# Verify all jobs deployed
kubectl get trainjobs --all-namespaces

echo "Job deployment completed at: $(date)"
```

#### Step 2.5: Initial Validation
```bash
# Check that all TrainJobs are starting properly
kubectl get trainjobs --all-namespaces | grep -v Running | grep -v Succeeded

# Verify pods are being created
kubectl get pods --all-namespaces | grep trainjob

# Check for any immediate errors
kubectl get events --all-namespaces | grep -i error | tail -20

echo "Initial validation completed at: $(date)"
```

### Phase 3: Post-Cutover Validation

#### Step 3.1: Comprehensive Validation
```bash
# Monitor all TrainJobs for thoroughly
kubectl get trainjobs --all-namespaces -w

# Validate training functionality
for job in $(kubectl get trainjobs --all-namespaces --no-headers | awk '{print $2}'); do
    echo "=== Validating $job ==="
    kubectl describe trainjob $job
    kubectl logs -l trainer.kubeflow.org/trainjob-name=$job --tail=50
done

# Performance comparison
echo "=== v2 Performance Results ===" > performance-v2.txt
kubectl top pods --all-namespaces | grep trainjob >> performance-v2.txt

# Compare with baseline
diff performance-baseline.txt performance-v2.txt > performance-comparison.txt
```

#### Step 3.2: Team Training & Documentation
```bash
# Update all documentation
find . -name "*.md" -exec sed -i 's/PyTorchJob/TrainJob/g' {} \;
find . -name "*.yaml" -exec sed -i 's/pytorchjob/trainjob/g' {} \;

# Update monitoring dashboards
# Update CI/CD pipelines
# Update deployment scripts
```

#### Step 3.3: Optimization
```bash
# Identify optimization opportunities
# - Custom runtime configurations
# - Resource optimization
# - Python SDK integration opportunities

# Implement optimizations based on v2 capabilities
```

## 🔧 Emergency Procedures

### If Issues Arise During Cutover

#### Immediate Rollback (early in cutover process)
```bash
cd rollback-plan
./rollback-to-v1.sh

# Verify rollback successful
kubectl get pytorchjobs --all-namespaces
kubectl get deployment -n opendatahub kubeflow-training-operator
```

#### Partial Recovery (Issues with specific jobs)
```bash
# If only some jobs fail, identify and fix individually
kubectl get trainjobs --all-namespaces | grep -E "(Failed|Error)"

# For each failed job, check conversion
kubectl describe trainjob failed-job-name

# Fix conversion issues and redeploy
python3 tools/convert-pytorch.py --fix failed-job-original.yaml failed-job-fixed.yaml
kubectl apply -f failed-job-fixed.yaml
```

## 📊 Validation Checklist

### Technical Validation
- [ ] All TrainJobs deploy without errors
- [ ] Training pods start successfully
- [ ] Training logs show expected progress
- [ ] Resource utilization within expected ranges
- [ ] GPU utilization (if applicable) matches baseline

### Functional Validation
- [ ] Training accuracy/loss metrics match v1 results
- [ ] Training time per epoch within ±10% of baseline
- [ ] Model checkpointing working correctly
- [ ] Data loading performance unchanged

### Operational Validation
- [ ] Team can operate TrainJobs without issues
- [ ] Monitoring/alerting working with new job types
- [ ] CI/CD pipelines deploying TrainJobs successfully
- [ ] Backup/restore procedures updated for TrainJobs

## 🚨 Common Issues & Solutions

### Issue: "ClusterTrainingRuntime not found"
```bash
# Solution: Reinstall base runtimes
kubectl apply -k https://github.com/kubeflow/trainer/manifests/base/runtimes --server-side=true
```

### Issue: Trainer controller not starting
```bash
# Check webhook certificate issues
kubectl describe deployment kubeflow-trainer-controller-manager -n opendatahub
kubectl logs deployment/kubeflow-trainer-controller-manager -n opendatahub

# Solution: Recreate webhook certificates
kubectl delete secret kubeflow-trainer-webhook-cert -n opendatahub
kubectl rollout restart deployment/kubeflow-trainer-controller-manager -n opendatahub
```

### Issue: Converted jobs have different resource allocation
```bash
# Compare resource specifications
kubectl get pytorchjob original-job -o yaml | grep -A 10 resources
kubectl get trainjob converted-job -o yaml | grep -A 10 resourcesPerNode

# Solution: Adjust resourcesPerNode to match v1 master resources
```

## 📈 Success Metrics

### Migration Success
- [ ] 100% of PyTorchJobs successfully converted to TrainJobs
- [ ] Zero failed job deployments post-cutover
- [ ] Maintenance window completed within planned timeframe

### Performance Success  
- [ ] Training performance within ±5% of v1 baseline
- [ ] Resource utilization equivalent or improved
- [ ] No regression in training accuracy/convergence

### Operational Success
- [ ] Team productivity restored within 1 week
- [ ] Zero critical issues requiring rollback
- [ ] CI/CD pipelines fully operational

## 🎯 Post-Migration Optimization

1. **Leverage v2 Features**
   ```bash
   # Explore Python SDK integration
   pip install kubeflow-training
   
   # Create custom training runtimes
   # Implement advanced scheduling features
   ```

2. **Performance Tuning**
   ```bash
   # Optimize resource allocations
   # Fine-tune runtime configurations
   # Implement auto-scaling if available
   ```

3. **Process Improvement**
   ```bash
   # Update team procedures
   # Enhance monitoring and alerting
   # Document lessons learned
   ```

---

## 📞 Emergency Support

### During Maintenance Window
- **Critical Issues**: Red Hat Emergency Support Line
- **Technical Issues**: Red Hat OpenShift AI Team escalation
- **Rollback Decision**: Follow documented rollback procedures

### Post-Migration Support
- **Standard Issues**: Red Hat Support Portal
- **Performance Issues**: Red Hat OpenShift AI Team
- **Community**: [Kubeflow Slack #kubeflow-trainer](https://kubeflow.slack.com)

**⚡ This strategy provides the fastest path to v2 with proper risk management and proven rollback procedures.**
