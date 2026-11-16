# AWS configuration tenant

Declarative AWS infrastructure for devantler-tech, managed as Crossplane-managed
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
  `oci://ghcr.io/devantler-tech/aws/manifests` (see the [CD workflow](.github/workflows/cd.yaml)),
  signed by the shared `publish-manifests.yaml` workflow in
  [`devantler-tech/.github`](https://github.com/devantler-tech/.github) at a pinned commit.
- The [platform](https://github.com/devantler-tech/platform) consumes the artifact via
  the `aws` tenant (Flux `OCIRepository` + `Kustomization` with cosign verification),
  and the in-cluster AWS Crossplane provider reconciles the resources against AWS.

Authentication (namespace, `SecretStore`, bootstrap-credential `ExternalSecret`, and
the `ProviderConfig`) is provisioned platform-side — see
[platform#2325](https://github.com/devantler-tech/platform/issues/2325).

## Inspect SES readiness

The separate [Inspect SES Account workflow](.github/workflows/inspect-ses-account.yaml)
reads the approved account in the fixed sending region after the typed confirmation
`inspect-ses-account`. It runs only from protected `main` as the maintainer, using the existing
identity with a session restricted to identity verification and the SES account read. Its cloud
job checks out no repository code and cannot request production access, change pricing or send mail.
The existing account setup workflow retains its separate purpose and confirmation.

The receipt contains readiness and review booleans, a closed review-status value, and numeric
quota fields.
The status is `PENDING`, `FAILED`, `GRANTED`, `DENIED` or `UNKNOWN` when absent. Missing required
fields, malformed metadata, a failed API call or an unexpected account fail the inspection.
An omitted optional review status yields `reviewKnown: false`; that is not evidence that an earlier
review has finished. Neither a sandbox result nor a pending review authorizes another request.
The read also does not prove an authenticated delivery or inbox placement.

Run `bash scripts/test-inspect-ses-account.sh` to exercise the actual scripts with synthetic API
responses and no AWS credentials or network calls. This needs Bash, `jq` and Mike Farah's `yq` v4.
The check validates source and session-policy boundaries before testing success, failure and
private-output handling. CI includes it in the required aggregate.

## Contributing

Follow [CONTRIBUTING.md](CONTRIBUTING.md) for a safe first change, local checks and submission.
The [CI workflow](.github/workflows/ci.yaml) checks rendering, validates every managed resource offline
against the schemas of the provider version the platform runs, and checks retired documentation
links. Passing it is not live AWS validation. The release workflow uses Conventional Commit titles to
decide whether a merge releases and which version it produces. Preserve the [Apache-2.0 license](LICENSE).
