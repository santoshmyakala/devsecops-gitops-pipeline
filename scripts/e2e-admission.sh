#!/usr/bin/env bash
# Assert admission decisions with server-side dry runs against a cluster running Kyverno + policies.
set -uo pipefail
FIXTURES=${1:-policies/tests/e2e/admission.yaml}
fail=0

check() { # name expected(allowed|denied) manifest
  local out
  if out=$(kubectl apply --dry-run=server -f - <<<"$3" 2>&1); then actual=allowed; else actual=denied; fi
  if [ "$actual" = "$2" ]; then
    printf 'PASS  %-28s %s\n' "$1" "$actual"
  else
    printf 'FAIL  %-28s expected %s, got %s\n%s\n' "$1" "$2" "$actual" "$out"; fail=1
  fi
}

kubectl create namespace e2e --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# Split the multi-document fixture file and check each document by its name prefix.
python3 - "$FIXTURES" > /tmp/fixtures.list <<'PY'
import sys, yaml, json
for doc in yaml.safe_load_all(open(sys.argv[1])):
    print(json.dumps(doc))
PY
while IFS= read -r doc; do
  name=$(jq -r .metadata.name <<<"$doc")
  case "$name" in allowed-*) exp=allowed ;; *) exp=denied ;; esac
  check "$name" "$exp" "$doc"
done < /tmp/fixtures.list

# Signed image path: only when a digest has been promoted to dev.
digest=$(yq -r '.image.digest' gitops/environments/dev/wine-quality-api.yaml)
if [[ "$digest" =~ ^sha256: ]]; then
  check "allowed-signed-wine-image" allowed "$(cat <<YAML
apiVersion: v1
kind: Pod
metadata: { name: allowed-signed-wine-image, namespace: e2e }
spec:
  securityContext: { runAsNonRoot: true, runAsUser: 10001 }
  containers:
    - name: api
      image: ghcr.io/santoshmyakala/wine-quality-mlops@${digest}
      securityContext: { allowPrivilegeEscalation: false }
      resources: { requests: { cpu: 50m, memory: 64Mi }, limits: { memory: 128Mi } }
YAML
)"
else
  echo "SKIP  allowed-signed-wine-image  (no digest promoted to dev yet)"
fi
exit $fail
