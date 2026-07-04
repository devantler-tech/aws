# aws

Declarative AWS infrastructure for devantler-tech, managed as Crossplane managed
resources and delivered GitOps-style.

## How it works

- **`deploy/`** holds the desired AWS state as [Crossplane](https://www.crossplane.io/)
  managed resources (provider-aws family). Manifests are namespace-agnostic — the
  platform injects the target namespace.
- **Releases** publish `deploy/` as a cosign-signed OCI manifests artifact at
  `oci://ghcr.io/devantler-tech/aws/manifests` (see `.github/workflows/cd.yaml`).
- The [platform](https://github.com/devantler-tech/platform) consumes the artifact via
  the `aws` tenant (Flux `OCIRepository` + `Kustomization` with cosign verification),
  and the in-cluster AWS Crossplane provider reconciles the resources against AWS.

Authentication (namespace, `SecretStore`, bootstrap-credential `ExternalSecret`, and
the `ProviderConfig`) is provisioned platform-side — see
[platform#2325](https://github.com/devantler-tech/platform/issues/2325).

## Contributing

Changes go through pull requests; `CI` validates that `deploy/` renders with
`kubectl kustomize`. Merges to `main` release automatically via semantic-release
(Conventional Commit titles decide the version).
