#!/usr/bin/env bash
# Ensure storage-infra dirs exist for Feast/dbt runtime data; migrate from repo paths once.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IFP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

for env in dev test prod; do
  feast_data="${IFP_ROOT}/storage-infra/feast/${env}/data"
  dbt_target="${IFP_ROOT}/storage-infra/dbt/${env}/target"
  dbt_logs="${IFP_ROOT}/storage-infra/dbt/${env}/logs"
  mkdir -p "${feast_data}" "${dbt_target}" "${dbt_logs}"
  touch "${feast_data}/.gitkeep" "${dbt_target}/.gitkeep" "${dbt_logs}/.gitkeep"

  legacy_feast="${IFP_ROOT}/feast/repos/${env}/data"
  if [[ -d "${legacy_feast}" ]] && [[ -n "$(ls -A "${legacy_feast}" 2>/dev/null || true)" ]]; then
    if [[ -z "$(ls -A "${feast_data}" 2>/dev/null | grep -v '^\.gitkeep$' || true)" ]]; then
      echo "[provision] Migrating ${legacy_feast} -> ${feast_data}"
      cp -a "${legacy_feast}/." "${feast_data}/"
    fi
  fi

  legacy_target="${IFP_ROOT}/dbt/feast_features/target"
  if [[ "${env}" == "dev" ]] && [[ -d "${legacy_target}" ]] && [[ -n "$(ls -A "${legacy_target}" 2>/dev/null || true)" ]]; then
    if [[ -z "$(ls -A "${dbt_target}" 2>/dev/null | grep -v '^\.gitkeep$' || true)" ]]; then
      echo "[provision] Migrating ${legacy_target} -> ${dbt_target}"
      cp -a "${legacy_target}/." "${dbt_target}/"
    fi
  fi
done

echo "[provision] storage-infra/feast/{dev,test,prod}/data and dbt/{dev,test,prod}/target ready"
