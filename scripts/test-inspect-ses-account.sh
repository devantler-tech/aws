#!/usr/bin/env bash
# Execute the actual workflow scripts with a local AWS stand-in and no credentials.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workflow=${1:-"$root/.github/workflows/inspect-ses-account.yaml"}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
[[ -f $workflow ]] || fail 'inspection workflow is missing'
yq -o=json '.' "$workflow" > "$work/workflow.json"
yq -o=json '.' "$root/.github/workflows/set-up-ses-account.yaml" > "$work/setup.json"
role=$(jq -er '.jobs["set-up"].env.ROLE_ARN' "$work/setup.json")
region=$(jq -er '.jobs["set-up"].env.AWS_REGION' "$work/setup.json")
setup_group=$(jq -er '.concurrency.group | select(type == "string" and length > 0)' "$work/setup.json")
account=${role#arn:aws:iam::}; account=${account%%:*}
[[ $account =~ ^[0-9]{12}$ && $region == eu-central-1 ]] || fail 'approved source binding is unavailable'

# Parse the workflow structure, including the policy, rather than looking for
# safe-looking words that a different runnable job could bypass.
jq -e --arg role "$role" --arg region "$region" --arg account "$account" --arg setup_group "$setup_group" '
  keys == ["concurrency","jobs","name","on","permissions"] and
  .concurrency == {group:"inspect-ses-account", "cancel-in-progress":false} and
  (.concurrency.group | ascii_downcase) != ($setup_group | ascii_downcase) and
  (.on | keys == ["workflow_dispatch"]) and
  (.on.workflow_dispatch.inputs | keys == ["confirm"]) and
  (.on.workflow_dispatch.inputs.confirm | .type == "string" and .required == true and (has("default") | not)) and
  .permissions == {} and
  (.jobs | keys == ["inspect"]) and
  (.jobs.inspect | ."runs-on" == "ubuntu-latest" and ."timeout-minutes" <= 10 and
    keys == ["env","name","permissions","runs-on","steps","timeout-minutes"] and
    .permissions == {"id-token":"write"} and
    .env.ROLE_ARN == $role and .env.AWS_REGION == $region and .env.EXPECTED_ACCOUNT_ID == $account and
    [.steps[].id] == ["guard", "credentials", "read"] and
    all(.steps[]; (has("if") | not)) and
    [.steps[] | select(has("uses")) | .id] == ["credentials"] and
    (.steps[0] | keys == ["env","id","name","run","shell"] and
      (.env | keys == ["CONFIRM"]) and .env.CONFIRM == "${{ inputs.confirm }}") and
    (.steps[2] | keys == ["id","name","run","shell"]) and
    (.steps[1] | keys == ["id","name","uses","with"] and
      .uses == "aws-actions/configure-aws-credentials@e1253824e5c10ff9df46874f81ed3ec929e19cfd" and
      (.with | keys == ["action-timeout-s","allowed-account-ids","aws-region","inline-session-policy","mask-aws-account-id","output-credentials","retry-max-attempts","role-duration-seconds","role-session-name","role-to-assume","translate-env-variables","unset-current-credentials"]) and
      .with."role-to-assume" == "${{ env.ROLE_ARN }}" and
      .with."aws-region" == "${{ env.AWS_REGION }}" and
      .with."allowed-account-ids" == "${{ env.EXPECTED_ACCOUNT_ID }}" and
      .with."mask-aws-account-id" == true and
      .with."unset-current-credentials" == true and
      .with."translate-env-variables" == false and
      .with."output-credentials" == false and
      .with."role-duration-seconds" == 900 and
      (.with."inline-session-policy" | fromjson) == {
        Version:"2012-10-17", Statement:[{
          Effect:"Allow", Action:["ses:GetAccount", "sts:GetCallerIdentity"], Resource:"*",
          Condition:{StringEquals:{"aws:RequestedRegion":$region}}
        }]
      }))
' "$work/workflow.json" > /dev/null || fail 'inspection source or permission boundary changed'
jq -er '.jobs.inspect.steps[] | select(.id == "guard") | .run | select(type == "string" and length > 0)' "$work/workflow.json" > "$work/guard.sh"
jq -er '.jobs.inspect.steps[] | select(.id == "read") | .run | select(type == "string" and length > 0)' "$work/workflow.json" > "$work/read.sh"
mkdir "$work/bin"
cat > "$work/bin/aws" <<'AWS'
#!/usr/bin/env bash
set -euo pipefail
[[ -z ${AWS_ACCESS_KEY_ID:-}${AWS_SECRET_ACCESS_KEY:-}${AWS_SESSION_TOKEN:-} ]] || exit 92
[[ $# == 11 && $3 == --region && $4 == eu-central-1 && $5 == --output && $6 == json && $7 == --no-cli-pager && $8 == --cli-connect-timeout && $9 == 10 && ${10} == --cli-read-timeout && ${11} == 20 ]] || exit 93
printf '%s %s\n' "$1" "$2" >> "$FIXTURE_DIR/calls"
case "$1 $2" in
  'sts get-caller-identity')
    [[ $FIXTURE_CASE != identity-api-failure ]] || { echo private-api-error-canary >&2; exit 9; }
    cat "$FIXTURE_DIR/identity.json" ;;
  'sesv2 get-account')
    [[ $FIXTURE_CASE != account-api-failure ]] || { echo private-api-error-canary >&2; exit 9; }
    cat "$FIXTURE_DIR/account.json" ;;
  *) echo forbidden-api >&2; exit 91 ;;
esac
AWS
chmod 0700 "$work/bin/aws"
test_path="$work/bin:$PATH"
reset_fixture() {
  printf '{"Account":"%s","Arn":"private-arn-canary","UserId":"private-user-canary"}\n' "$account" > "$work/identity.json"
  cat > "$work/account.json" <<'JSON'
{"ProductionAccessEnabled":false,"SendingEnabled":true,"EnforcementStatus":"HEALTHY","SendQuota":{"Max24HourSend":200,"MaxSendRate":1,"SentLast24Hours":0},"Details":{"ReviewDetails":{"Status":"PENDING","CaseId":"private-case-canary"},"UseCaseDescription":"private-message-canary","AdditionalContactEmailAddresses":["private-address-canary@example.invalid"]}}
JSON
  printf '{"inputs":{"confirm":"inspect-ses-account"}}\n' > "$work/event.json"
  : > "$work/calls"
}
run_script() {
  env -i PATH="$test_path" FIXTURE_DIR="$work" FIXTURE_CASE="$case_name" \
    EXPECTED_ACCOUNT_ID="$account" AWS_REGION="$region" \
    GITHUB_EVENT_PATH="$work/event.json" GITHUB_EVENT_NAME=workflow_dispatch \
    GITHUB_REF=refs/heads/main GITHUB_REPOSITORY=devantler-tech/aws \
    GITHUB_WORKFLOW_REF=devantler-tech/aws/.github/workflows/inspect-ses-account.yaml@refs/heads/main \
    GITHUB_ACTOR=devantler GITHUB_RUN_ATTEMPT=1 RUNNER_ENVIRONMENT=github-hosted \
    CONFIRM=inspect-ses-account "$@"
}
private_free() {
  ! grep -Eq "private-.*-canary|$account|arn:|@example.invalid|AccessKey|SecretAccess|SessionToken" "$work/stdout" "$work/stderr" || fail 'private data reached a receipt'
}
receipt_shape() {
  jq -e -s 'length == 1 and (.[0] |
    keys == ["enforcementHealthy","max24HourSend","maxSendRate","productionAccessEnabled","reviewKnown","reviewPending","reviewStatus","sendingEnabled","sentLast24Hours"] and
    ([.productionAccessEnabled,.sendingEnabled,.enforcementHealthy,.reviewKnown,.reviewPending] | all(.[]; type == "boolean")) and
    (.reviewStatus | IN("PENDING","FAILED","GRANTED","DENIED","UNKNOWN")) and
    ([.max24HourSend,.maxSendRate,.sentLast24Hours] | all(.[]; type == "number")))' "$work/stdout" >/dev/null || fail 'receipt is not exactly the fixed public shape'
}
for case_name in pending granted failed denied unknown-review missing-review-details missing-review-status unlimited; do
  reset_fixture
  case "$case_name" in
    granted) jq '.ProductionAccessEnabled=true | .SendingEnabled=false | .EnforcementStatus="PROBATION" | .Details.ReviewDetails.Status="GRANTED" | .SendQuota.MaxSendRate=14.5' "$work/account.json" > "$work/changed.json"; mv "$work/changed.json" "$work/account.json" ;;
    failed) jq '.Details.ReviewDetails.Status="FAILED"' "$work/account.json" > "$work/changed.json"; mv "$work/changed.json" "$work/account.json" ;;
    denied) jq '.Details.ReviewDetails.Status="DENIED"' "$work/account.json" > "$work/changed.json"; mv "$work/changed.json" "$work/account.json" ;;
    unknown-review) jq 'del(.Details)' "$work/account.json" > "$work/changed.json"; mv "$work/changed.json" "$work/account.json" ;;
    missing-review-details) jq 'del(.Details.ReviewDetails)' "$work/account.json" > "$work/changed.json"; mv "$work/changed.json" "$work/account.json" ;;
    missing-review-status) jq 'del(.Details.ReviewDetails.Status)' "$work/account.json" > "$work/changed.json"; mv "$work/changed.json" "$work/account.json" ;;
    unlimited) jq '.SendQuota.Max24HourSend=-1' "$work/account.json" > "$work/changed.json"; mv "$work/changed.json" "$work/account.json" ;;
  esac
  run_script bash "$work/guard.sh" > "$work/stdout" 2> "$work/stderr" || fail "valid guard refused: $case_name"
  [[ ! -s $work/stdout && ! -s $work/stderr ]] || fail 'guard emitted data'
  run_script bash "$work/read.sh" > "$work/stdout" 2> "$work/stderr" || fail "valid inspection refused: $case_name"
  [[ $(cat "$work/calls") == $'sts get-caller-identity\nsesv2 get-account' ]] || fail 'inspection used an unexpected API sequence'
  receipt_shape
  case "$case_name" in
    pending) jq -e '.productionAccessEnabled == false and .sendingEnabled == true and .enforcementHealthy == true and .reviewKnown == true and .reviewPending == true and .reviewStatus == "PENDING" and .max24HourSend == 200 and .maxSendRate == 1 and .sentLast24Hours == 0' "$work/stdout" >/dev/null || fail 'pending fields were changed' ;;
    granted) jq -e '.productionAccessEnabled == true and .sendingEnabled == false and .enforcementHealthy == false and .reviewKnown == true and .reviewPending == false and .reviewStatus == "GRANTED" and .maxSendRate == 14.5' "$work/stdout" >/dev/null || fail 'granted fields were changed' ;;
    failed) jq -e '.reviewKnown == true and .reviewPending == false and .reviewStatus == "FAILED"' "$work/stdout" >/dev/null || fail 'failed review status was changed' ;;
    denied) jq -e '.reviewKnown == true and .reviewPending == false and .reviewStatus == "DENIED"' "$work/stdout" >/dev/null || fail 'denied review status was changed' ;;
    unknown-review|missing-review-details|missing-review-status) jq -e '.reviewKnown == false and .reviewPending == false and .reviewStatus == "UNKNOWN"' "$work/stdout" >/dev/null || fail 'missing review invented a known decision' ;;
    unlimited) jq -e '.max24HourSend == -1' "$work/stdout" >/dev/null || fail 'documented unlimited quota was changed' ;;
  esac
  [[ ! -s $work/stderr ]] || fail 'success wrote a diagnostic'
  private_free
done

for case_name in wrong-account identity-api-failure identity-malformed identity-missing identity-number identity-multiple account-api-failure malformed multiple non-object missing-production null-production string-sending missing-quota string-quota negative-quota infinite-quota missing-rate missing-sent unknown-enforcement malformed-details malformed-review unknown-review-status null-review-status; do
  reset_fixture
  case "$case_name" in
    wrong-account) printf '{"Account":"000000000000"}\n' > "$work/identity.json" ;;
    identity-malformed) printf 'private-error-canary\n' > "$work/identity.json" ;;
    identity-missing) printf '{}\n' > "$work/identity.json" ;;
    identity-number) printf '{"Account":123}\n' > "$work/identity.json" ;;
    identity-multiple) printf '{}\n' >> "$work/identity.json" ;;
    malformed) printf 'private-error-canary\n' > "$work/account.json" ;;
    multiple) printf '{}\n' >> "$work/account.json" ;;
    non-object) printf '[]\n' > "$work/account.json" ;;
    missing-production) filter='del(.ProductionAccessEnabled)' ;;
    null-production) filter='.ProductionAccessEnabled=null' ;;
    string-sending) filter='.SendingEnabled="false"' ;;
    missing-quota) filter='del(.SendQuota)' ;;
    string-quota) filter='.SendQuota.Max24HourSend="200"' ;;
    negative-quota) filter='.SendQuota.Max24HourSend=-2' ;;
    infinite-quota) filter='.SendQuota.MaxSendRate=1e999' ;;
    missing-rate) filter='del(.SendQuota.MaxSendRate)' ;;
    missing-sent) filter='del(.SendQuota.SentLast24Hours)' ;;
    unknown-enforcement) filter='.EnforcementStatus="private-status-canary"' ;;
    malformed-details) filter='.Details=[]' ;;
    malformed-review) filter='.Details.ReviewDetails="PENDING"' ;;
    unknown-review-status) filter='.Details.ReviewDetails.Status="private-status-canary"' ;;
    null-review-status) filter='.Details.ReviewDetails.Status=null' ;;
  esac
  if [[ -n ${filter:-} ]]; then jq "$filter" "$work/account.json" > "$work/changed.json"; mv "$work/changed.json" "$work/account.json"; unset filter; fi
  status=0
  run_script bash "$work/read.sh" > "$work/stdout" 2> "$work/stderr" || status=$?
  [[ $status != 0 && ! -s $work/stdout ]] || fail "invalid metadata accepted: $case_name"
  if [[ $case_name == wrong-account || $case_name == identity-* ]]; then
    [[ $(cat "$work/calls") == 'sts get-caller-identity' ]] || fail 'account read reached after identity refusal'
  else
    [[ $(cat "$work/calls") == $'sts get-caller-identity\nsesv2 get-account' ]] || fail 'failure used an unexpected API sequence'
  fi
  grep -Eq '^SES_ACCOUNT_INSPECTION=UNVERIFIED stage=(identity|account|metadata)$' "$work/stderr" || fail 'failure diagnostic is not fixed'
  private_free
done

for case_name in branch repository workflow actor retry runner event confirmation extra-input malformed-event missing-event arguments; do
  reset_fixture
  override=()
  case "$case_name" in
    branch) override=(GITHUB_REF=refs/heads/topic) ;;
    repository) override=(GITHUB_REPOSITORY=someone/aws) ;;
    workflow) override=(GITHUB_WORKFLOW_REF=devantler-tech/aws/.github/workflows/set-up-ses-account.yaml@refs/heads/main) ;;
    actor) override=(GITHUB_ACTOR=someone) ;;
    retry) override=(GITHUB_RUN_ATTEMPT=2) ;;
    runner) override=(RUNNER_ENVIRONMENT=self-hosted) ;;
    event) override=(GITHUB_EVENT_NAME=push) ;;
    confirmation) override=(CONFIRM=set-up-ses-account) ;;
    extra-input) printf '{"inputs":{"confirm":"inspect-ses-account","mode":"setup"}}\n' > "$work/event.json" ;;
    malformed-event) printf 'private-event-canary\n' > "$work/event.json" ;;
    missing-event) rm "$work/event.json" ;;
  esac
  arguments=(); [[ $case_name != arguments ]] || arguments=(setup)
  status=0
  run_script env "${override[@]}" bash "$work/guard.sh" "${arguments[@]}" > "$work/stdout" 2> "$work/stderr" || status=$?
  [[ $status != 0 && ! -s $work/stdout && ! -s $work/calls ]] || fail "unsafe dispatch accepted: $case_name"
  [[ $(cat "$work/stderr") == SES_ACCOUNT_INSPECTION=REFUSED ]] || fail 'dispatch diagnostic is not fixed'
  private_free
done

# These fixtures must fail the structural gate before any script/API runs.
# The optional file argument prevents recursive negative-control generation.
if [[ $# == 0 ]]; then
  for boundary in policy role mutable-action extra-job cloud-checkout guard-bypass concurrency-collision; do
    case "$boundary" in
      policy) change='.jobs.inspect.steps[1].with["inline-session-policy"] |= (fromjson | .Statement[0].Action += ["ses:PutAccountDetails"] | tojson)' ;;
      role) change='.jobs.inspect.env.ROLE_ARN = "arn:aws:iam::000000000000:role/different"' ;;
      mutable-action) change='.jobs.inspect.steps[1].uses = "aws-actions/configure-aws-credentials@main"' ;;
      extra-job) change='.jobs.mutate = {steps:[{run:"aws sesv2 put-account-details"}]}' ;;
      cloud-checkout) change='.jobs.inspect.steps += [{uses:"actions/checkout@main"}]' ;;
      guard-bypass) change='.jobs.inspect.steps[1].if = "always()"' ;;
      concurrency-collision) change=".concurrency.group = \$setup_group" ;;
    esac
    jq --arg setup_group "$setup_group" "$change" "$work/workflow.json" > "$work/boundary.yaml"
    status=0
    bash "$root/scripts/test-inspect-ses-account.sh" "$work/boundary.yaml" > "$work/boundary.log" 2>&1 || status=$?
    [[ $status != 0 ]] || fail "unsafe source fixture accepted: $boundary"
    grep -q '^FAIL: inspection source or permission boundary changed$' "$work/boundary.log" || fail "source fixture failed outside the structural gate: $boundary"
  done
fi
printf '%s\n' 'PASS: isolated SES inspection, exact policy, dispatch refusal, API ordering, metadata and private-output controls'
