#!/usr/bin/env bash
# Validate the rendered deploy/ output against the Crossplane package schemas declared in
# .github/crossplane-validate/extensions.yaml, offline (aws#50).
#
# `kubectl kustomize deploy/` proves only that the files render. A misspelt forProvider field,
# a wrong apiVersion or a field the provider dropped renders fine, merges, releases, and is
# first rejected by the cluster, which stops the whole tenant reconciling. This check reports
# those on the pull request instead. It needs no cloud credentials and no cluster; it does
# download the package schemas from their registries.
#
# Usage: validate-crossplane-schemas.sh <crossplane-binary> [rendered-manifests-file]
#   Without a file, deploy/ is rendered with `kubectl kustomize`.
#   CROSSPLANE_IMAGE (required) — the Crossplane image whose built-in schemas are used, pinned
#   to the version the platform runs.
# Exit status: 0 every resource validated; non-zero on any schema error, any missing schema
# (a resource kind no declared package defines), or a failed render or download.
set -euo pipefail
crossplane="${1:?pass the crossplane CLI binary}"
image="${CROSSPLANE_IMAGE:?set CROSSPLANE_IMAGE to the pinned Crossplane image}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
rendered="${2:-}"
if [[ -z "$rendered" ]]; then
  rendered="$work/rendered.yaml"
  kubectl kustomize "$root/deploy" > "$rendered"
fi
[[ -s "$rendered" ]] || { echo "FAIL: no rendered manifests to validate" >&2; exit 2; }
"$crossplane" resource validate \
  "$root/.github/crossplane-validate/extensions.yaml" "$rendered" \
  --error-on-missing-schemas \
  --crossplane-image "$image" \
  --cache-dir "$work/cache"
