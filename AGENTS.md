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
- **Schema check:** CI also validates the rendered `deploy/` output offline against the
  provider package declared in `.github/crossplane-validate/extensions.yaml`, with the
  pinned Crossplane CLI (`scripts/test-validate-crossplane-schemas.sh <crossplane-binary>`,
  `CROSSPLANE_IMAGE` set as in `ci.yaml`). It catches unknown fields, wrong `apiVersion`s
  and kinds with no schema; it is not live AWS validation and does not prove the tenant
  reconciles. Keep that file's provider version equal to the platform's pin; CI warns on a
  mismatch.
- **Layout:** all managed resources live under `deploy/`, referenced from
  `deploy/kustomization.yaml`. Keep manifests namespace-agnostic (the platform-side
  tenant Kustomization injects the namespace).
- **What this tenant may own:** today, only the account's GitHub Actions OIDC identity
  provider (`OpenIDConnectProvider`). The platform decides which AWS resource kinds are
  active and which of them this tenant may write. The EKS CI `Role` and its permissions
  boundary stay platform-owned on purpose, because the cap on what that identity may create
  lives inside the `Role`.
- **Adding a new resource kind takes two PRs, platform first:** the platform activates the
  kind and grants this tenant permission to manage it; only after that merges does the
  manifest land here. A manifest for a kind the tenant may not write passes this
  repository's CI and releases, then the platform refuses it and the whole `aws` tenant
  stops reconciling.
- **Auth wiring is platform-side** (namespace, `SecretStore`, bootstrap-credential
  `ExternalSecret`, `ProviderConfig` — platform#2325/#2412): do NOT add credentials or
  provider config here.
- **Release flow:** squash-merge with a Conventional-Commit PR title → semantic-release
  cuts the version on `main` push → the `v*` tag triggers `cd.yaml`, which publishes and
  cosign-signs the artifact via the shared `publish-manifests.yaml` workflow in
  `devantler-tech/.github`. The signing identity is that workflow's path at the pinned
  commit (`devantler-tech/.github/.github/workflows/publish-manifests.yaml@<sha>`), and the
  platform `aws` tenant's verifier must accept it. Dependabot bumps that pin; the platform's
  accepted revisions must include a bumped commit before a release ships with it.
- **Required check:** `CI - Required Checks` (org ruleset).
- **No secrets in this repo** — AWS credentials come from OpenBao via the platform;
  anything credential-shaped in a manifest is a bug.
- **Documentation links:** required CI scans README and AGENTS with the pinned retired
  repository validator and `.github/retired-repo-links.json`. The offline regression
  `bash scripts/test-retired-repo-links.sh <released-validator-binary>` checks clean
  content, retired links in both files, and missing configuration.
