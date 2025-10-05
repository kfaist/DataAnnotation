#!/usr/bin/env bash
set -euo pipefail

# =================== Config ===================
REPO_SLUG="kfaist/DataAnnotation"
BRANCH="labelstudio-ephemeral"
WORKFLOW_PATH=".github/workflows/labelstudio_ephemeral.yml"
WORKFLOW_FILE_BASENAME="labelstudio_ephemeral.yml"
ASSIST_MAX_SUBMISSIONS="3"
TMPROOT="$(mktemp -d)"
RUN_A_LABEL="assist-only"
RUN_B_LABEL="submit-capped"
GIT_NAME="${GIT_NAME:-ci-bot}"
GIT_EMAIL="${GIT_EMAIL:-ci-bot@users.noreply.github.com}"

# =================== Checks ===================
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }; }
for bin in gh git jq unzip python3 pip; do need "$bin"; done
gh auth status >/dev/null || { echo "GitHub CLI not authenticated. Run: gh auth login"; exit 1; }

# =================== Clone branch ===================
echo "Cloning $REPO_SLUG#$BRANCH ..."
git -c protocol.version=2 clone --filter=blob:none --branch "$BRANCH" "https://github.com/$REPO_SLUG.git" "$TMPROOT/repo"
cd "$TMPROOT/repo"
# Use tokened remote for push
if gh auth status >/dev/null 2>&1; then
  TOKEN="$(gh auth token)"
  git remote set-url origin "https://x-access-token:${TOKEN}@github.com/${REPO_SLUG}.git"
fi
git config user.name "$GIT_NAME"
git config user.email "$GIT_EMAIL"

# =================== 1) Normalize workflows ===================
root_dupe_commit_url="n/a"
if [ -f "$WORKFLOW_FILE_BASENAME" ]; then
  echo "Removing stray root-level workflow copy: $WORKFLOW_FILE_BASENAME"
  git rm -f "$WORKFLOW_FILE_BASENAME"
  git commit -m "ci: remove stray root-level workflow copy"
  git push origin "$BRANCH"
  root_dupe_commit_sha="$(git rev-parse HEAD)"
  root_dupe_commit_url="https://github.com/${REPO_SLUG}/commit/${root_dupe_commit_sha}"
fi

mkdir -p .github/workflows
removed_any=0
for f in .github/workflows/*; do
  if [ -e "$f" ] && [ "$(basename "$f")" != "$WORKFLOW_FILE_BASENAME" ]; then
    echo "Removing other workflow: $f"
    git rm -f "$f"
    removed_any=1
  fi
done
if [ "$removed_any" -eq 1 ]; then
  git commit -m "ci: normalize workflows (keep only ${WORKFLOW_FILE_BASENAME})"
  git push origin "$BRANCH"
fi

# =================== 2) Patch 'Seed admin and project' step ===================
if [ ! -f "$WORKFLOW_PATH" ]; then
  echo "ERROR: $WORKFLOW_PATH not found on branch $BRANCH"; exit 1
fi

# Install ruamel.yaml for round‑trip safe YAML edit (preserves formatting/anchors as much as possible).
python3 - <<'PY' >/dev/null 2>&1 || pip install --disable-pip-version-check --no-input ruamel.yaml jq
import sys
PY

python3 - "$WORKFLOW_PATH" <<'PY'
import sys, io
from ruamel.yaml import YAML
from ruamel.yaml.scalarstring import PreservedScalarString as PSS

wf_path = sys.argv[1]
yaml = YAML()
yaml.preserve_quotes = True
yaml.width = 100000

with open(wf_path, 'r', encoding='utf-8') as f:
    data = yaml.load(f)

if not data or 'jobs' not in data:
    print("ERROR: YAML missing 'jobs'", file=sys.stderr); sys.exit(2)

new_run = PSS(r'''set -euo pipefail
command -v jq >/dev/null 2>&1 || { sudo apt-get update -y && sudo apt-get install -y jq; }

base="http://127.0.0.1:8080"
email="admin@test.local"
pass="TempPass!123"

# Wait up to ~${WAIT_LOOPS:-90}*2s for Label Studio to be up
echo "Waiting up to $(( ${WAIT_LOOPS:-90} * 2 ))s for Label Studio to be up..."
for i in $(seq 1 ${WAIT_LOOPS:-90}); do
  if curl -fsS "$base/" >/dev/null 2>&1; then
    echo "Label Studio healthy"
    break
  fi
  sleep 2
  if [ "$i" -eq "${WAIT_LOOPS:-90}" ]; then
    echo "ERROR: Label Studio did not become healthy"
    exit 1
  fi
done

# Signup (ignore non-2xx; log status)
echo "Signup..."
scode=$(curl -sS -o /dev/null -w "%{http_code}" \
  -X POST "$base/user/signup" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$email\",\"password\":\"$pass\"}" || true)
echo "signup status=$scode"

# Login (no --fail); capture Set-Cookie case-insensitively
echo "Login..."
resp=$(curl -sS -i -X POST "$base/user/login" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$email\",\"password\":\"$pass\"}")
echo "$resp" | sed -n '1,40p'
cookie=$(echo "$resp" | awk 'BEGIN{IGNORECASE=1} /^set-cookie:/ {print $2}' | tr -d '\r' | head -n1 | cut -d';' -f1)
if [ -z "${cookie:-}" ]; then
  echo "ERROR: no session cookie returned from login"
  exit 1
fi

# Create API token
echo "Create token..."
token_json=$(curl -sS -X POST "$base/api/users/me/tokens" -H "Cookie: $cookie" \
  -H 'Content-Type: application/json' -d '{"name":"ci"}')
token=$(echo "$token_json" | jq -r '.key // empty')
if [ -z "${token:-}" ]; then
  echo "ERROR: token creation failed: $token_json"
  exit 1
fi

# Create simple text/choices project
cfg='<View><Text name="text" value="$text"/><Choices name="label" toName="text" choice="single" required="true"><Choice value="Positive"/><Choice value="Negative"/></Choices></View>'
pj=$(jq -n --arg title "CI Demo" --arg cfg "$cfg" '{title:$title, label_config:$cfg}' | \
  curl -sS -X POST "$base/api/projects" -H "Authorization: Token '"$token"'" -H 'Content-Type: application/json' -d @-)
pid=$(echo "$pj" | jq -r '.id // empty')
if [ -z "${pid:-}" ]; then
  echo "ERROR: could not extract project id: $pj"
  exit 1
fi

# Seed 5 tasks
cat > tasks.json <<'JSON'
[{"data":{"text":"AI art wins an award at a major festival."}},
{"data":{"text":"Nonprofit launches an AI tool for grant review."}},
{"data":{"text":"Backlash grows over AI-generated illustrations."}},
{"data":{"text":"New dataset supports accessibility research."}},
{"data":{"text":"Artists demand better consent controls for training."}}]
JSON
curl -sS -X POST "$base/api/projects/$pid/tasks/bulk" -H "Authorization: Token $token" \
  -H 'Content-Type: application/json' --data-binary @tasks.json >/dev/null

echo "token=$token" >> "$GITHUB_OUTPUT"
echo "pid=$pid" >> "$GITHUB_OUTPUT"
echo "base=$base" >> "$GITHUB_OUTPUT"
''')

found = False
for job_name, job in (data.get('jobs') or {}).items():
    steps = (job or {}).get('steps') or []
    for step in steps:
        if isinstance(step, dict) and step.get('name') == 'Seed admin and project':
            step['run'] = new_run
            # Ensure shell/env are present
            step.setdefault('shell', 'bash')
            env = step.setdefault('env', {})
            # Wait loop default 90; can be overridden at workflow/job/step level
            env.setdefault('WAIT_LOOPS', '90')
            found = True

if not found:
    print("ERROR: Could not find step named 'Seed admin and project' to patch.", file=sys.stderr)
    sys.exit(3)

with open(wf_path, 'w', encoding='utf-8') as f:
    yaml.dump(data, f)
PY

git add "$WORKFLOW_PATH"
git commit -m "ci(ephemeral): robust signup/login; longer health wait; case-insensitive cookie."
git push origin "$BRANCH"
robust_commit_sha="$(git rev-parse HEAD)"
robust_commit_url="https://github.com/${REPO_SLUG}/commit/${robust_commit_sha}"

# =================== 3) Dispatch two runs via API (no UI) ===================
echo "Resolving workflow id for $WORKFLOW_PATH ..."
WID="$(gh api "repos/${REPO_SLUG}/actions/workflows" -q ".workflows[] | select(.path==\"${WORKFLOW_PATH}\") | .id")"
if [ -z "${WID:-}" ]; then echo "ERROR: Could not resolve workflow id"; exit 1; fi

list_runs_ids() {
  gh api "repos/${REPO_SLUG}/actions/workflows/${WID}/runs" \
    -F branch="$BRANCH" -F per_page=20 -q '.workflow_runs[].id'
}
before_ids="$(list_runs_ids | tr '\n' ' ')"

dispatch_and_wait() {
  local assist="$1" label="$2"
  echo "Dispatching run ($label) assist_mode=$assist ..."
  gh api -X POST "repos/${REPO_SLUG}/actions/workflows/${WID}/dispatches" \
    -f ref="$BRANCH" -f inputs[assist_mode]="$assist" -f inputs[max_submissions]="$ASSIST_MAX_SUBMISSIONS" >/dev/null

  # Find the new run id (compare to previous set)
  local rid=""
  for _ in $(seq 1 120); do
    sleep 2
    for id in $(list_runs_ids); do
      if [[ " $before_ids " != *" $id "* ]]; then rid="$id"; break; fi
    done
    [ -n "$rid" ] && break
  done
  [ -z "$rid" ] && { echo "ERROR: Timed out discovering new run id for $label"; exit 1; }
  before_ids="$before_ids $rid"

  # Poll to completion
  local status conclusion url
  while :; do
    read -r status conclusion url <<<"$(gh api "repos/${REPO_SLUG}/actions/runs/${rid}" -q '[.status, .conclusion, .html_url] | @tsv')"
    printf "Run %s status=%s conclusion=%s\r" "$rid" "$status" "${conclusion:-n/a}"
    [ "$status" = "completed" ] && { echo; break; }
    sleep 5
  done
  echo "$rid|$url|${conclusion:-n/a}"
}

IFS='|' read -r runA_id runA_url runA_conc <<<"$(dispatch_and_wait true  "$RUN_A_LABEL")"
IFS='|' read -r runB_id runB_url runB_conc <<<"$(dispatch_and_wait false "$RUN_B_LABEL")"

# Optional: if run failed due to "Seed admin and project", bump WAIT_LOOPS to 120 and retry once
maybe_retry_seed_fail() {
  local rid_ref="$1" rid conc url
  IFS='|' read -r rid url conc <<<"$rid_ref"
  if [ "$conc" != "success" ]; then
    # Inspect step conclusions
    failed_seed="$(gh api "repos/${REPO_SLUG}/actions/runs/${rid}/jobs" \
      -q '.jobs[].steps[] | select(.name=="Seed admin and project" and .conclusion=="failure") | .name')"
    if [ -n "$failed_seed" ]; then
      echo "Detected failure at 'Seed admin and project'. Bumping WAIT_LOOPS to 120 and retrying once..."
      python3 - "$WORKFLOW_PATH" <<'PY'
import sys
from ruamel.yaml import YAML
from ruamel.yaml.scalarstring import PreservedScalarString as PSS

wf_path = sys.argv[1]
yaml = YAML()
with open(wf_path, 'r', encoding='utf-8') as f:
    data = yaml.load(f)

for job in (data.get('jobs') or {}).values():
    for step in (job or {}).get('steps') or []:
        if isinstance(step, dict) and step.get('name') == 'Seed admin and project':
            env = step.setdefault('env', {})
            env['WAIT_LOOPS'] = '120'

with open(wf_path, 'w', encoding='utf-8') as f:
    yaml.dump(data, f)
PY
      git add "$WORKFLOW_PATH"
      git commit -m "ci(ephemeral): extend health wait to ~240s on seed retry"
      git push origin "$BRANCH"
      # Redispatch same mode as rid
      mode="true"; [ "$rid" = "$runB_id" ] && mode="false"
      IFS='|' read -r nrid nurl nconc <<<"$(dispatch_and_wait "$mode" "retry")"
      echo "$nrid|$nurl|$nconc"
      return 0
    fi
  fi
  echo "$rid|$url|$conc"
}

IFS='|' read -r runA_id runA_url runA_conc <<<"$(maybe_retry_seed_fail "$runA_id|$runA_url|$runA_conc")"
IFS='|' read -r runB_id runB_url runB_conc <<<"$(maybe_retry_seed_fail "$runB_id|$runB_url|$runB_conc")"

# =================== 4) Fetch artifacts & report ===================
fetch_summary() {
  local rid="$1"
  local aid
  aid="$(gh api "repos/${REPO_SLUG}/actions/runs/${rid}/artifacts" \
    -q '.artifacts[] | select(.name=="labelstudio-ephemeral-summary") | .id' | head -n1)"
  [ -z "$aid" ] && { echo "ERROR: No labelstudio-ephemeral-summary artifact for run $rid" >&2; return 1; }
  local zf="$TMPROOT/${rid}.zip"
  gh api -H "Accept: application/octet-stream" "repos/${REPO_SLUG}/actions/artifacts/${aid}/zip" > "$zf"
  local outdir="$TMPROOT/${rid}"
  mkdir -p "$outdir"
  unzip -q "$zf" -d "$outdir"
  # find summary
  local jf
  jf="$( (ls "$outdir"/**/labelstudio-summary.json 2>/dev/null || true) | head -n1 )"
  [ -z "$jf" ] && { echo "ERROR: labelstudio-summary.json not found in artifact of run $rid" >&2; return 1; }
  echo "$jf"
}

summA_path="$(fetch_summary "$runA_id")" || true
summB_path="$(fetch_summary "$runB_id")" || true

echo
echo "================ DELIVERABLES ================"
echo "Root-level removal commit: ${root_dupe_commit_url}"
echo "Robust seed step commit:   ${robust_commit_url}"
echo
echo "Run A (${RUN_A_LABEL}):"
echo "  run_id: ${runA_id}"
echo "  url:    ${runA_url}"
if [ -n "${summA_path:-}" ] && [ -f "$summA_path" ]; then
  echo "  labelstudio-summary.json (first 20 lines):"
  sed -n '1,20p' "$summA_path"
else
  echo "  labelstudio-summary.json: (missing)"
fi
echo
echo "Run B (${RUN_B_LABEL}):"
echo "  run_id: ${runB_id}"
echo "  url:    ${runB_url}"
if [ -n "${summB_path:-}" ] && [ -f "$summB_path" ]; then
  echo "  labelstudio-summary.json (first 20 lines):"
  sed -n '1,20p' "$summB_path"
else
  echo "  labelstudio-summary.json: (missing)"
fi

# Validate acceptance criteria
pass=true
if [ -f "${summA_path:-/dev/null}" ]; then
  # Expect: login_ok=true; tasks_discovered>0; tasks_prefilled>0; submissions_attempted=0; submissions_succeeded=0; errors=[]
  Aok="$(jq -e '(.login_ok==true) and ((.tasks_discovered|tonumber? // .)>0) and ((.tasks_prefilled|tonumber? // .)>0) and (.submissions_attempted==0) and (.submissions_succeeded==0) and ((.errors|length)==0)' "$summA_path" >/dev/null && echo ok || echo bad)"
  [ "$Aok" != "ok" ] && pass=false
else pass=false; fi
if [ -f "${summB_path:-/dev/null}" ]; then
  # Expect: submissions_attempted=3 (or <= available); submissions_succeeded≥1; errors=[]
  Bok="$(jq -e '((.submissions_attempted|tonumber? // .) >= 1) and ((.submissions_attempted|tonumber? // .) <= 3) and ((.submissions_succeeded|tonumber? // .) >= 1) and ((.errors|length)==0)' "$summB_path" >/dev/null && echo ok || echo bad)"
  [ "$Bok" != "ok" ] && pass=false
else pass=false; fi

# If failed, show last 20 log lines of failing run
if [ "$pass" = true ] && [ "$runA_conc" = "success" ] && [ "$runB_conc" = "success" ]; then
  echo
  echo "One-line status: Demo PASS"
else
  echo
  echo "One-line status: Demo FAILED"
  # Prefer show last 20 lines for whichever failed, B then A
  fail_rid="$runB_id"; [ "$runA_conc" != "success" ] && fail_rid="$runA_id"
  echo "Last 20 log lines for run ${fail_rid}:"
  gh run view "$fail_rid" --repo "$REPO_SLUG" --log | tail -n 20 || true
  echo
  echo "Recommended tweak: If failure occurred during Label Studio readiness, increase WAIT_LOOPS to 120 (already auto-applied on retry). If login cookie was missing, ensure upstream Label Studio returns Set-Cookie and the base URL is reachable from the job network."
fi
