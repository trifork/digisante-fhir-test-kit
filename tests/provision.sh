#!/usr/bin/env bash
# Build and start the test-kit stack (db + fhir) with the CH EMR IG loaded,
# then wait until the server and the loaded profiles are ready.
#
# Provider-agnostic: set COMPOSE to "podman-compose", "podman compose", or
# "docker compose". Defaults to podman-compose (used in the multipass VM and CI).
set -euo pipefail

cd "$(dirname "$0")/.."

export HAPI_VERSION="${HAPI_VERSION:-v8.4.0-3}"
export IMAGE_VERSION="${IMAGE_VERSION:-0.1.0}"
export FHIR_PORT="${FHIR_PORT:-8080}"
# CH EMR Implementation Guide (https://hl7ch.github.io/ch-emr).
export IG_URLS="${IG_URLS:-ch.fhir.ig.ch-emr@1.0.0-ballot=https://hl7ch.github.io/ch-emr/package.tgz}"

COMPOSE="${COMPOSE:-podman-compose}"

echo "Provisioning stack with: $COMPOSE"
echo "  HAPI_VERSION=$HAPI_VERSION  IMAGE_VERSION=$IMAGE_VERSION"
echo "  IG_URLS=$IG_URLS"

# shellcheck disable=SC2086
$COMPOSE up -d --build

# Container runtime used for diagnostics / fail-fast (podman or docker).
RT=""
if command -v podman >/dev/null 2>&1; then RT=podman; elif command -v docker >/dev/null 2>&1; then RT=docker; fi

dump_logs() {
  [ -n "$RT" ] || return 0
  echo "----- container status -----"
  $RT ps -a 2>/dev/null || true
  for c in $($RT ps -a --format '{{.Names}}' 2>/dev/null | grep -iE 'fhir|db'); do
    echo "----- logs: $c (tail 200) -----"
    $RT logs --tail 200 "$c" 2>&1 || true
  done
}

# True if the fhir container has exited/died (boot-time IG install is fatal, so a
# crash means the server will never come up — fail fast instead of waiting).
fhir_crashed() {
  [ -n "$RT" ] || return 1
  $RT ps -a --format '{{.Names}} {{.Status}}' 2>/dev/null \
    | grep -i fhir | grep -qiE 'exited|dead'
}

# The server only starts serving after boot-time IG install completes, and with
# transitive dependencies that means downloading/installing ~10-15 packages, so
# allow generous time.
echo -n "Waiting for FHIR server "
up=0
for _ in $(seq 1 240); do
  if curl -sf "http://localhost:${FHIR_PORT}/fhir/metadata" >/dev/null 2>&1; then echo " ready"; up=1; break; fi
  if fhir_crashed; then echo " CRASHED"; dump_logs; exit 1; fi
  echo -n "."
  sleep 5
done
if [ "$up" != 1 ]; then echo " TIMEOUT"; dump_logs; exit 1; fi

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

echo "Provisioning complete."
