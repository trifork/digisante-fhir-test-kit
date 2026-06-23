#!/usr/bin/env bash
# Provider-agnostic test assertions against a running test-kit stack.
# Assumes the stack is already up (see provision.sh) with the CH EMR IG loaded.
#
#   FHIR_BASE  default http://localhost:8080/fhir
#
# Exit code is non-zero if any assertion fails.
set -uo pipefail

FHIR_BASE="${FHIR_BASE:-http://localhost:8080/fhir}"

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
no() { echo "  FAIL: $1"; fail=$((fail + 1)); }

jq_py() { python3 -c "$1"; } # read JSON on stdin, run python snippet

echo "FHIR_BASE=$FHIR_BASE"
echo

echo "[1] Server capability statement"
rt=$(curl -s "$FHIR_BASE/metadata" | jq_py 'import sys,json; print(json.load(sys.stdin).get("resourceType",""))' 2>/dev/null)
[ "$rt" = "CapabilityStatement" ] && ok "metadata is a CapabilityStatement" || no "metadata not a CapabilityStatement (got '$rt')"

# Look a specific StructureDefinition up by canonical URL; echoes its Bundle.total.
sd_count() {
  local enc
  enc=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1")
  curl -s "$FHIR_BASE/StructureDefinition?url=$enc&_summary=count" \
    | jq_py 'import sys,json; print(json.load(sys.stdin).get("total",0))' 2>/dev/null
}

CH_EMR_COMPOSITION="http://fhir.ch/ig/ch-emr/StructureDefinition/ch-emr-composition"
IPS_COMPOSITION="http://hl7.org/fhir/uv/ips/StructureDefinition/Composition-uv-ips"

echo "[2] CH EMR IG and its dependencies are installed"
# HAPI only returns Bundle.total when asked with _summary=count. Query specific
# canonicals (robust regardless of how many StructureDefinitions/pages exist).
total=$(curl -s "$FHIR_BASE/StructureDefinition?_summary=count" | jq_py 'import sys,json; print(json.load(sys.stdin).get("total",0))' 2>/dev/null)
{ [ -n "$total" ] && [ "$total" -gt 0 ]; } && ok "StructureDefinitions present (total=$total)" || no "no StructureDefinitions loaded"
[ "$(sd_count "$CH_EMR_COMPOSITION")" = "1" ] && ok "CH EMR profile present (ch-emr-composition)" || no "CH EMR profile ch-emr-composition not found"
# The IPS Composition profile arrives only as a transitive dependency of CH EMR
# (and is the target of an imposeProfile extension) — so its presence proves
# dependency installation worked.
[ "$(sd_count "$IPS_COMPOSITION")" = "1" ] && ok "dependency profile present (Composition-uv-ips from hl7.fhir.uv.ips)" || no "dependency profile Composition-uv-ips not found"

echo "[3] Profile-restricted validation enforces the profile (and imposed profiles)"
enc=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$CH_EMR_COMPOSITION")
invalid=$(curl -s -X POST "$FHIR_BASE/Composition/\$validate?profile=$enc" \
  -H 'Content-Type: application/fhir+json' -d '{"resourceType":"Composition"}')
irt=$(printf '%s' "$invalid" | jq_py 'import sys,json; print(json.load(sys.stdin).get("resourceType",""))' 2>/dev/null)
ierrs=$(printf '%s' "$invalid" | jq_py 'import sys,json; d=json.load(sys.stdin); print(sum(1 for i in d.get("issue",[]) if i.get("severity") in ("error","fatal")))' 2>/dev/null)
imposed=$(printf '%s' "$invalid" | jq_py 'import sys,json; d=json.load(sys.stdin); print(sum(1 for i in d.get("issue",[]) if "uv/ips" in json.dumps(i)))' 2>/dev/null)
[ "$irt" = "OperationOutcome" ] && ok "\$validate returns an OperationOutcome" || no "\$validate did not return an OperationOutcome"
{ [ -n "$ierrs" ] && [ "$ierrs" -gt 0 ]; } && ok "empty Composition rejected by profile ($ierrs error issue(s))" || no "empty Composition was not rejected"
{ [ -n "$imposed" ] && [ "$imposed" -gt 0 ]; } && ok "imposed IPS profile enforced ($imposed issue(s) from Composition-uv-ips)" || no "imposed IPS profile not enforced"

echo
echo "================================"
echo "Passed: $pass   Failed: $fail"
echo "================================"
[ "$fail" -eq 0 ]
