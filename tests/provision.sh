#!/usr/bin/env bash
# Build and start the test-kit stack (db + fhir + ui) with the CH EMR IG loaded,
# then wait until the server, the loaded profiles, and the UI are all ready.
#
# Provider-agnostic: set COMPOSE to "podman-compose", "podman compose", or
# "docker compose". Defaults to podman-compose (used in the multipass VM and CI).
set -euo pipefail

cd "$(dirname "$0")/.."

export HAPI_VERSION="${HAPI_VERSION:-v8.4.0-3}"
export IMAGE_VERSION="${IMAGE_VERSION:-0.1.0}"
export FHIR_PORT="${FHIR_PORT:-8080}"
export UI_PORT="${UI_PORT:-8888}"
# CH EMR Implementation Guide (https://hl7ch.github.io/ch-emr).
export IG_URLS="${IG_URLS:-ch.fhir.ig.ch-emr@1.0.0-ballot=https://hl7ch.github.io/ch-emr/package.tgz}"

COMPOSE="${COMPOSE:-podman-compose}"

echo "Provisioning stack with: $COMPOSE"
echo "  HAPI_VERSION=$HAPI_VERSION  IMAGE_VERSION=$IMAGE_VERSION"
echo "  IG_URLS=$IG_URLS"

# shellcheck disable=SC2086
$COMPOSE up -d --build

wait_for() {
  local label=$1 url=$2 tries=$3
  echo -n "Waiting for $label "
  for _ in $(seq 1 "$tries"); do
    if curl -sf "$url" >/dev/null 2>&1; then echo " ready"; return 0; fi
    echo -n "."
    sleep 5
  done
  echo " TIMEOUT"
  return 1
}

wait_for "FHIR server" "http://localhost:${FHIR_PORT}/fhir/metadata" 60

# The CH EMR IG plus its dependencies take a while to download and install on the
# first boot; poll until constraint profiles appear.
echo -n "Waiting for IG profiles to install "
for _ in $(seq 1 120); do
  # Bundle.total is only returned with _summary=count.
  n=$(curl -s "http://localhost:${FHIR_PORT}/fhir/StructureDefinition?_summary=count" \
    | python3 -c 'import sys,json; print(json.load(sys.stdin).get("total",0))' 2>/dev/null || echo 0)
  if [ "${n:-0}" -gt 0 ]; then echo " ready (total=$n)"; break; fi
  echo -n "."
  sleep 5
done

wait_for "UI" "http://localhost:${UI_PORT}/" 30

echo "Provisioning complete."
