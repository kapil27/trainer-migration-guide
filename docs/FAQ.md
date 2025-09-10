# Frequently Asked Questions - PyTorch Migration

## 🎯 General Migration Questions

### Q: Can I run PyTorchJobs and TrainJobs at the same time?
**A:** Yes! Both Training Operator v1 and Kubeflow Trainer v2 can coexist.

### Q: Will my PyTorch training results be identical after migration?
**A:** Yes, training functionality and results should be identical. The underlying PyTorch distributed training mechanism is the same - only the orchestration layer changes.

### Q: Do I need to modify my PyTorch training code?
**A:** No! Your existing Docker images and training scripts work unchanged. No code modifications needed.

### Q: How long does migration typically take?
**A:** 
- **Side-by-Side Strategy**: 4-6 hours duration for gradual migration
- **Complete Replacement**: 2-3 hours duration with maintenance window

## 🔧 Technical Questions

### Q: What happens to Master and Worker configurations?
**A:** In v2, there's no distinction between Master and Worker. TrainJob uses `numNodes` for total node count and applies the same configuration to all nodes.

```yaml
# v1: Different specs for Master/Worker
pytorchReplicaSpecs:
  Master: {replicas: 1, template: {...}}
  Worker: {replicas: 3, template: {...}}

# v2: Unified configuration
trainer:
  numNodes: 4  # Total nodes
  # Single config applied to all nodes
```

### Q: What if my Master and Worker need different resources?
**A:** v2 applies the same resources to all nodes. Solutions:
1. **Use maximum resources** for all nodes
2. **Create custom runtime** for different resource profiles
3. **Contact Red Hat support** for advanced configurations

### Q: Which runtime should I use for my PyTorch jobs?
- **CPU training**: `torch-distributed`
- **GPU training**: `torch-cuda-251` (or `torch-cuda-241` for older CUDA)
- **DeepSpeed**: `deepspeed-distributed`

### Q: How do I handle elastic training?
**A:** v1 elastic training requires custom runtime configuration in v2. Contact Red Hat support for assistance with elastic workload migration.

### Q: What about volume mounts and ConfigMaps?
**A:** They work the same way. Volume mounts are defined at the trainer level and applied to all nodes.

```yaml
trainer:
  volumes:
    - name: dataset
      persistentVolumeClaim:
        claimName: training-data
  volumeMounts:
    - name: dataset
      mountPath: /data
```

## 🚀 Migration Strategy Questions

### Q: Which migration strategy should I choose?
**A:** 
- **Choose Side-by-Side** if you want zero downtime, gradual learning, and full rollback capability
- **Choose Complete Replacement** if you need fast migration (2-3 duration) and can tolerate a maintenance window

### Q: Can I rollback if migration fails?
**A:** 
- **Side-by-Side**: Yes, complete rollback capability since v1 remains installed
- **Complete Replacement**: Rollback requires restoring from backup

### Q: How do I test the conversion before production migration?
**A:** 
1. Convert jobs with the automation tool
2. Deploy v2 jobs with different names (add `-v2` suffix)
3. Compare training logs and results
4. Validate performance metrics match

## 🛠️ Tool and Automation Questions

### Q: Does the conversion tool handle all PyTorchJob configurations?
**A:** The tool handles 90% of common configurations automatically:
- ✅ Single node and distributed training
- ✅ Resource specifications
- ✅ Environment variables
- ✅ GPU configurations
- ⚠️ Elastic training requires manual review
- ⚠️ Complex volume configurations may need adjustment

### Q: How do I convert multiple jobs at once?
**A:** Use the batch conversion feature:
```bash
python3 tools/convert-pytorch.py --directory ./all-pytorch-jobs --output-dir ./converted-jobs
```

### Q: What if the conversion tool fails?
**A:** 
1. Check the error message for specific issues
2. Manually review the original PyTorchJob for unsupported configurations
3. See [examples/pytorch-examples/](../examples/pytorch-examples/) for reference
4. Contact support for complex scenarios

## 🔍 Troubleshooting Questions

### Q: "ClusterTrainingRuntime not found" error
**A:** Install the base runtimes:
```bash
kubectl apply -k https://github.com/kubeflow/trainer/manifests/base/runtimes --server-side=true
```

### Q: TrainJob pods are not starting
**A:** Check:
1. Runtime exists: `kubectl get clustertrainingruntime`
2. Resource availability: `kubectl describe node`
3. Image pull issues: `kubectl describe pod <failed-pod>`

### Q: Training results differ between v1 and v2
**A:** Compare:
1. Environment variables: `kubectl describe pod` for both v1 and v2
2. Resource allocations: Ensure v2 resources match v1
3. Runtime configuration: `kubectl describe clustertrainingruntime`

### Q: Performance is worse in v2
**A:** 
1. Verify resource allocation matches v1
2. Check if GPU runtime is being used for GPU workloads
3. Review runtime configuration for optimization opportunities

## 📊 Operational Questions

### Q: How do I update my CI/CD pipelines?
**A:** 
1. Replace `PyTorchJob` with `TrainJob` in YAML templates
2. Update `apiVersion` to `trainer.kubeflow.org/v1alpha1`
3. Update monitoring to query `trainjobs` instead of `pytorchjobs`

### Q: What about monitoring and alerting?
**A:** 
1. Update dashboards to monitor TrainJob metrics
2. Adjust alert rules for new resource names
3. Pod labels change - update log aggregation queries

### Q: How do I backup TrainJobs?
**A:** Same as PyTorchJobs:
```bash
kubectl get trainjobs --all-namespaces -o yaml > trainjobs-backup.yaml
```

## 🎓 Learning Questions

### Q: Where can I learn more about TrainJob APIs?
**A:** 
- [Kubeflow Trainer Documentation](https://www.kubeflow.org/docs/components/trainer/)
- [TrainJob Examples](../examples/pytorch-examples/)
- [Complete Migration Guide](COMPLETE_MIGRATION_GUIDE.md)

### Q: What's the difference between TrainingRuntime and ClusterTrainingRuntime?
**A:** 
- **ClusterTrainingRuntime**: Available cluster-wide, managed by platform team
- **TrainingRuntime**: Namespace-scoped, for team-specific configurations

### Q: Can I create custom training runtimes?
**A:** Yes! Create custom ClusterTrainingRuntime or TrainingRuntime resources for specialized configurations. Contact Red Hat support for guidance.

## 🔒 Security Questions

### Q: Are there any security differences between v1 and v2?
**A:** v2 generally has improved security:
- Better RBAC integration
- Enhanced webhook validation
- Improved secret handling

### Q: Do service accounts need to be updated?
**A:** You may need additional permissions for TrainJob resources:
```bash
kubectl auth can-i create trainjobs
kubectl auth can-i get clustertrainingruntimes
```

## 📈 Performance Questions

### Q: Is v2 faster than v1?
**A:** Performance is typically equivalent with potential improvements:
- Better pod scheduling
- Enhanced resource management
- Optimized communication patterns

### Q: How do I optimize TrainJob performance?
**A:** 
1. Choose appropriate runtime for your workload
2. Right-size resources per node
3. Use GPU runtimes for GPU workloads
4. Consider custom runtimes for specific optimizations

## 🆘 Support Questions

### Q: When should I contact Red Hat support?
**A:** Contact support for:
- Custom runtime requirements
- Complex migration scenarios
- Performance optimization needs
- Issues not covered in documentation

### Q: What information should I provide to support?
**A:** 
1. Current PyTorchJob configurations
2. Conversion tool output and errors
3. TrainJob manifests that fail
4. Environment validation results
5. Specific error messages

### Q: Is community support available?
**A:** Yes! Join [Kubeflow Slack #kubeflow-trainer](https://kubeflow.slack.com) for community discussions and support.

---

## 📞 Still Have Questions?

- **Quick Issues**: Check [Quick Reference](QUICK_REFERENCE.md)
- **Detailed Guide**: See [Complete Migration Guide](COMPLETE_MIGRATION_GUIDE.md)  
- **Examples**: Browse [PyTorch Examples](../examples/pytorch-examples/)
- **Red Hat Support**: Contact your Red Hat OpenShift AI support team

**💡 Tip**: Most questions are answered by running the validation tool: `./tools/validate-readiness.sh`
