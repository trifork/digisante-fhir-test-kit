#!/usr/bin/env bash
# Provider-agnostic test assertions against a running test-kit stack.
# Assumes the stack is already up (see provision.sh) with the CH EMR IG loaded.
#
#   FHIR_BASE  default http://localhost:8080/fhir
#   UI_BASE    default http://localhost:8888
#
# Exit code is non-zero if any assertion fails.
set -uo pipefail

FHIR_BASE="${FHIR_BASE:-http://localhost:8080/fhir}"
UI_BASE="${UI_BASE:-http://localhost:8888}"

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
no() { echo "  FAIL: $1"; fail=$((fail + 1)); }

jq_py() { python3 -c "$1"; } # read JSON on stdin, run python snippet

echo "FHIR_BASE=$FHIR_BASE"
echo "UI_BASE=$UI_BASE"
echo

echo "[1] Server capability statement"
rt=$(curl -s "$FHIR_BASE/metadata" | jq_py 'import sys,json; print(json.load(sys.stdin).get("resourceType",""))' 2>/dev/null)
[ "$rt" = "CapabilityStatement" ] && ok "metadata is a CapabilityStatement" || no "metadata not a CapabilityStatement (got '$rt')"

echo "[2] CH EMR Implementation Guide loaded"
# HAPI only returns Bundle.total when asked with _summary=count.
total=$(curl -s "$FHIR_BASE/StructureDefinition?_summary=count" | jq_py 'import sys,json; print(json.load(sys.stdin).get("total",0))' 2>/dev/null)
profiles=$(curl -s "$FHIR_BASE/StructureDefinition?_count=200")
chcount=$(printf '%s' "$profiles" | jq_py 'import sys,json; d=json.load(sys.stdin); print(sum(1 for e in d.get("entry",[]) if "ch-emr" in (e["resource"].get("url") or "")))' 2>/dev/null)
{ [ -n "$total" ] && [ "$total" -gt 0 ]; } && ok "StructureDefinitions present (total=$total)" || no "no StructureDefinitions loaded"
{ [ -n "$chcount" ] && [ "$chcount" -gt 0 ]; } && ok "CH EMR profiles present (count=$chcount)" || no "no ch-emr profiles found"

echo "[3] Profile-restricted validation enforces the profile"
# Pick a CH EMR constraint profile (prefer a resource type with mandatory base
# elements, so an empty instance is guaranteed to fail validation), then $validate
# an empty resource of that type against the profile.
read -r prof_url prof_type <<EOF
$(printf '%s' "$profiles" | jq_py 'import sys,json
d=json.load(sys.stdin)
cands=[(e["resource"]["url"], e["resource"].get("type","")) for e in d.get("entry",[])
       if "ch-emr" in (e["resource"].get("url") or "") and e["resource"].get("type") not in ("Extension","")]
pref=[c for c in cands if c[1] in ("Composition","Observation","MedicationStatement","DocumentReference")]
chosen=(pref or cands or [("","")])[0]
print(chosen[0], chosen[1])' 2>/dev/null)
EOF

if [ -n "$prof_url" ] && [ -n "$prof_type" ]; then
  ok "discovered CH EMR profile to validate: $prof_type ($prof_url)"
  enc=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$prof_url")
  invalid=$(curl -s -X POST "$FHIR_BASE/${prof_type}/\$validate?profile=$enc" \
    -H 'Content-Type: application/fhir+json' \
    -d "{\"resourceType\":\"${prof_type}\"}")
  irt=$(printf '%s' "$invalid" | jq_py 'import sys,json; print(json.load(sys.stdin).get("resourceType",""))' 2>/dev/null)
  ierrs=$(printf '%s' "$invalid" | jq_py 'import sys,json; d=json.load(sys.stdin); print(sum(1 for i in d.get("issue",[]) if i.get("severity") in ("error","fatal")))' 2>/dev/null)
  [ "$irt" = "OperationOutcome" ] && ok "\$validate returns an OperationOutcome" || no "\$validate did not return an OperationOutcome"
  { [ -n "$ierrs" ] && [ "$ierrs" -gt 0 ]; } && ok "empty ${prof_type} rejected by profile ($ierrs error issue(s))" || no "empty ${prof_type} was not rejected"
else
  no "no CH EMR constraint profile discovered to validate against"
fi

echo "[4] Custom UI serves the SPA and proxies the FHIR API"
curl -s "$UI_BASE/" | grep -q "FHIR Test Kit" && ok "UI serves the SPA" || no "UI did not serve the SPA"
uirt=$(curl -s "$UI_BASE/fhir/metadata" | jq_py 'import sys,json; print(json.load(sys.stdin).get("resourceType",""))' 2>/dev/null)
[ "$uirt" = "CapabilityStatement" ] && ok "UI proxies /fhir to the server" || no "UI /fhir proxy failed (got '$uirt')"

echo
echo "================================"
echo "Passed: $pass   Failed: $fail"
echo "================================"
[ "$fail" -eq 0 ]
