# Release Notes v1.7.2

## Feast/dbt runtime data outside images (Compose + Kubeflow)

### Main features

#### storage-infra layout for Feast and dbt artifacts
- Feast runtime data: `storage-infra/feast/{dev,test,prod}/data/` (registry, parquet, online store).
- dbt runtime data: `storage-infra/dbt/{env}/target/` and `logs/`.
- Compose `feast-{env}` and `dbt-{env}` sidecars bind-mount these paths over repo `data/` and `target/`.

#### Kubeflow pipeline-runner image (code only)
- `tpa-pipeline-runner` ships dbt/Feast **project code** only (`.dockerignore` excludes data).
- Pipeline pods mount host-backed PVCs (`ifp-feast-runtime-data`, `ifp-dbt-runtime-data`).
- kind `extraMounts` expose `storage-infra` on the kind node; provision script migrates legacy repo paths.

#### Scripts
- `kubernetes/provision-pipeline-runtime-data.sh` — create dirs + one-time migrate from `feast/repos/*/data` and `dbt/feast_features/target`.
- `kubernetes/install-pipeline-data-volumes.sh` — apply PV/PVC in namespace `kubeflow`.
- `kubernetes/generate-kind-config.sh` — kind cluster config with runtime data mounts.

### Migration notes

1. **Provision data dirs:** `bash kubernetes/provision-pipeline-runtime-data.sh`
2. **Recreate kind** (if cluster predates extraMounts): `kind delete cluster --name trading-cluster` then `bash kubernetes/start-kubernetes.sh`
3. **Rebuild pipeline image:** `bash kubernetes/build-pipeline-image.sh dev && bash kubernetes/deploy-pipeline-image-to-kind.sh`
4. **Recreate Compose sidecars** so new volume mounts apply.

### Breaking changes

- None for URLs. Feast/dbt **code** paths unchanged; runtime artifacts move to `storage-infra/` (auto-migrated on first provision).

---

**Tag:** v1.7.2  
**Date:** 2026-07-02  
**Branch:** main
