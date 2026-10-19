#!/usr/bin/env bash
# Prove the schema gate blocks: the real deploy/ output passes, while an unknown forProvider
# field and a kind no declared package defines each fail with their own diagnostic.
set -euo pipefail
crossplane="${1:?pass the crossplane CLI binary}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
check="$root/scripts/validate-crossplane-schemas.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
bash "$check" "$crossplane"
kubectl kustomize "$root/deploy" > "$work/clean.yaml"
grep -q '^  forProvider:$' "$work/clean.yaml" || { echo 'FAIL: fixture base has no forProvider block'; exit 1; }
awk '{ print } /^  forProvider:$/ { print "    notARealField: true" }' "$work/clean.yaml" > "$work/unknown-field.yaml"
sed 's#^apiVersion: iam\.aws\.m\.upbound\.io/v1beta1$#apiVersion: iam.aws.m.upbound.io/v1beta9#' \
  "$work/clean.yaml" > "$work/missing-schema.yaml"
! cmp -s "$work/clean.yaml" "$work/missing-schema.yaml" || { echo 'FAIL: missing-schema fixture is unchanged'; exit 1; }
expect_failure() { # <fixture> <diagnostic>
  local status=0
  bash "$check" "$crossplane" "$work/$1" > "$work/$1.log" 2>&1 || status=$?
  cat "$work/$1.log"
  [[ "$status" != 0 ]] || { echo "FAIL: $1 passed the schema gate"; exit 1; }
  grep -qF -- "$2" "$work/$1.log" || { echo "FAIL: $1 failed without the expected diagnostic: $2"; exit 1; }
}
expect_failure unknown-field.yaml 'unknown field: "notARealField"'
expect_failure missing-schema.yaml 'could not find CRD/XRD for: iam.aws.m.upbound.io/v1beta9'
echo 'PASS: clean deploy/, an unknown forProvider field and a missing schema'
