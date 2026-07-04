# AGENTS.md — devantler-tech/aws

Conventions for AI agents working in this repo. This is the canonical instructions
file; the portfolio-wide engineering contract lives in the
[monorepo `AGENTS.md`](https://github.com/devantler-tech/monorepo/blob/main/AGENTS.md)
and applies here in full (draft-PR autonomy, trust gate, Conventional-Commit PR
titles, root-cause fixes, never hand-edit generated files).

## What this repo is

The devantler-tech **AWS config tenant**: desired AWS state as Crossplane managed
resources in `deploy/`, published on release as a cosign-signed OCI manifests
artifact (`oci://ghcr.io/devantler-tech/aws/manifests`) that the
[platform](https://github.com/devantler-tech/platform) `aws` tenant reconciles.
It mirrors the `devantler-tech/.github` repo's `github-config` tenant pattern.

## Maintenance

- **Validate before every PR:** `kubectl kustomize deploy/ > /dev/null` (what CI runs).
  Crossplane CRD semantics are validated on-cluster, not here.
- **Layout:** all managed resources live under `deploy/`, referenced from
  `deploy/kustomization.yaml`. Keep manifests namespace-agnostic (the platform-side
  tenant Kustomization injects the namespace).
- **Auth wiring is platform-side** (namespace, `SecretStore`, bootstrap-credential
  `ExternalSecret`, `ProviderConfig` — platform#2325/#2412): do NOT add credentials or
  provider config here.
- **Release flow:** squash-merge with a Conventional-Commit PR title → semantic-release
  cuts the version on `main` push → the `v*` tag triggers `cd.yaml`, which publishes and
  cosign-signs the artifact via the shared `publish-manifests.yaml` workflow in
  `devantler-tech/actions`. The signing identity is that workflow's path — the platform
  verifier must match it.
- **Required check:** `CI - Required Checks` (org ruleset).
- **No secrets in this repo** — AWS credentials come from OpenBao via the platform;
  anything credential-shaped in a manifest is a bug.
