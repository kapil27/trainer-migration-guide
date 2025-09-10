# Migration Testing Artifacts

This directory contains all artifacts generated during the validation testing of both migration strategies on Red Hat OpenShift AI.

## 📁 Directory Structure

```
migration-testing/
├── strategy-a/                    # Strategy A (Side-by-Side) testing artifacts
│   ├── phase1-backups/            # Initial PyTorchJob backups
│   ├── backups/                   # Live migration tool backups
│   └── phase2-converted-trainjobs.yaml # Converted TrainJobs from Strategy A
├── strategy-b/                    # Strategy B (Complete Replacement) testing artifacts
│   ├── strategyb-backups/         # PyTorchJob backups before removal
│   ├── strategyb-converted/       # Batch converted TrainJobs
│   ├── strategyb-individual/      # Individual job extractions
│   └── strategyb-final/           # Final TrainJob manifests deployed
└── artifacts/                     # Shared testing artifacts
```

## 🎯 Purpose

These artifacts serve as:

- **📚 Testing Evidence**: Proof of successful migration strategy validation
- **🔄 Reproducibility**: Enable reproduction of migration testing
- **📊 Analysis**: Support detailed comparison between strategies
- **🛠️ Debugging**: Reference for troubleshooting migration issues
- **📖 Documentation**: Real-world examples of migration artifacts

## 🧪 Testing Summary

### Strategy A Results
- **Duration**: ~45 minutes
- **Approach**: Side-by-side deployment
- **Success Rate**: 100%
- **Key Artifacts**: Live migration backups, converted TrainJobs

### Strategy B Results  
- **Duration**: ~15 minutes
- **Approach**: Complete replacement
- **Success Rate**: 100%
- **Key Artifacts**: Pre-migration backups, final TrainJob deployments

## 📋 Usage

### For Reproduction
```bash
# Strategy A artifacts
ls migration-testing/strategy-a/

# Strategy B artifacts  
ls migration-testing/strategy-b/
```

### For Analysis
```bash
# Compare conversion outputs
diff migration-testing/strategy-a/phase2-converted-trainjobs.yaml \
     migration-testing/strategy-b/strategyb-converted/all-trainjobs.yaml
```

### For Reference
- Use backup files as templates for similar migrations
- Reference conversion outputs for validation
- Study final manifests for deployment patterns

## 🔗 Related Documentation

- **[Test Results](../test-results/)** - Detailed testing reports
- **[Migration Strategies](../migration-strategies/)** - Strategy documentation
- **[Tools](../tools/)** - Automation scripts used in testing

---

**Note**: These artifacts are from live testing on Red Hat OpenShift AI and demonstrate real-world migration scenarios.
