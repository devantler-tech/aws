# Contributing to the AWS configuration tenant

You can help by clarifying a desired-state explanation or improving a focused manifest example.
Discuss substantial changes in an [issue](https://github.com/devantler-tech/aws/issues) first:
this configuration is consumed by the portfolio's platform. Report sensitive vulnerabilities
through this repository's private
[Report a vulnerability](https://github.com/devantler-tech/aws/security/advisories/new) form,
not a public issue or PR.

## Make a first documentation change

You need Git and `kubectl` with built-in Kustomize. This first path needs no submodules, cloud
credentials, AWS CLI, production cluster or publishing access.

Fork `devantler-tech/aws` on GitHub. Replace `YOUR-LOGIN` with your login:

```sh
git clone https://github.com/YOUR-LOGIN/aws.git
cd aws
git switch -c docs/first-contribution
```

Make a small wording improvement in `README.md` without changing the render command or deployment
architecture. From the repository root, run the required local baseline:

```sh
kubectl kustomize deploy/ > /dev/null
git diff --check
```

Both commands must exit successfully; the render is deliberately quiet. It validates the local
Kustomize build, not AWS API access or live reconciliation.
[CI](.github/workflows/ci.yaml) also validates each managed resource offline against its Crossplane
provider schema, which catches unknown fields and wrong API versions, scans documentation for retired
repository links, and checks positive and negative fixtures for both checks. Native CI and exact-head substantive review remain
separate merge gates.

## Keep configuration and operations separate

Read [AGENTS.md](AGENTS.md) before changing managed resources. Place them under `deploy/` and
include them in its Kustomization. Keep manifests namespace-agnostic: the platform injects the
namespace and owns provider authentication. Never add cloud credentials, secrets or provider
configuration here, and never hand-edit generated files.

Publishing the signed artifact and applying or reconciling it are maintainer operations, not
onboarding steps. Do not run an apply command against a production cluster to validate a first PR.
The [README architecture](README.md#how-it-works) explains the platform boundary.

## Submit your change

Review the diff, configure commit signing and stage only your changed paths. Use a Conventional
Commit subject describing the outcome. For the README-only first change above:

```sh
git add README.md
git commit -S -m "docs: clarify local manifest validation"
git push -u origin docs/first-contribution
```

Open a **draft** PR to `devantler-tech/aws:main` using the inherited
[PR template](https://github.com/devantler-tech/.github/blob/main/.github/PULL_REQUEST_TEMPLATE.md).
Keep Why/What focused on the reader-facing problem and outcome, link the issue for substantial
work, and put detailed validation evidence in a PR comment or check summary. Disclose AI assistance
when used. Address findings; required CI and a successful substantive review of the exact current
head must pass before merge. Follow the inherited
[code of conduct](https://github.com/devantler-tech/.github/blob/main/.github/CODE_OF_CONDUCT.md)
and preserve the [Apache-2.0 license](LICENSE).
