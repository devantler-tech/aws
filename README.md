# AWS configuration tenant

Declarative AWS infrastructure for devantler-tech, managed as Crossplane managed
resources and delivered GitOps-style.

This is the portfolio's desired-state configuration, not a general-purpose AWS provisioning CLI.
Start with a local render; applying it requires the separately managed platform and authorized
cloud access.

## Render locally

You need Git and `kubectl` with its built-in Kustomize command. No AWS credentials, AWS CLI or
running cluster are needed for this check. From a directory where you want a source checkout:

```sh
git clone https://github.com/devantler-tech/aws.git
cd aws
kubectl kustomize deploy/ > /dev/null
```

Success is a zero exit status with no output. This builds the checked-in manifest set; it does not
apply resources, validate installed Crossplane CRD semantics, verify cloud permissions or prove
the live tenant reconciles. Keep cloud credentials and provider authentication out of this repository.

## How it works

- **`deploy/`** holds the desired AWS state as [Crossplane](https://www.crossplane.io/)
  managed resources (provider-aws family). Manifests are namespace-agnostic — the
  platform injects the target namespace.
- The **release pipeline** publishes `deploy/` as a cosign-signed OCI manifests artifact at
  `oci://ghcr.io/devantler-tech/aws/manifests` (see the [CD workflow](.github/workflows/cd.yaml)).
- The [platform](https://github.com/devantler-tech/platform) consumes the artifact via
  the `aws` tenant (Flux `OCIRepository` + `Kustomization` with cosign verification),
  and the in-cluster AWS Crossplane provider reconciles the resources against AWS.

Authentication (namespace, `SecretStore`, bootstrap-credential `ExternalSecret`, and
the `ProviderConfig`) is provisioned platform-side — see
[platform#2325](https://github.com/devantler-tech/platform/issues/2325).

## Contributing

Follow [CONTRIBUTING.md](CONTRIBUTING.md) for a safe first change, local checks and submission.
The [CI workflow](.github/workflows/ci.yaml) checks rendering and retired documentation links;
passing it is not live AWS validation. The release workflow uses Conventional Commit titles to
decide whether a merge releases and which version it produces. Preserve the [Apache-2.0 license](LICENSE).
