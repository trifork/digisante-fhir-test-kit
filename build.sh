#!/usr/bin/env bash
set -euo pipefail

# Build the DigiSanté FHIR Test Kit image from source.
#
# Local builds use a distinct "local" tag scheme (an unqualified image name with
# the LOCAL_TAG tag, default "local") so they never collide with the published
# GHCR images (versioned tags like 1.0.0, or latest) and are never pushed.
# The selected HAPI FHIR version (HAPI_VERSION) is baked into the image.
#
# This is equivalent to:
#   docker compose -f docker-compose.yml -f docker-compose.build.yml build

cd "$(dirname "$0")"

# Load .env if present (without clobbering values already in the environment).
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

HAPI_VERSION="${HAPI_VERSION:-v8.4.0-3}"
LOCAL_IMAGE="${LOCAL_IMAGE:-digisante-fhir-test-kit}"
LOCAL_TAG="${LOCAL_TAG:-local}"

FHIR_IMAGE="${LOCAL_IMAGE}:${LOCAL_TAG}"

echo "Building FHIR server image: ${FHIR_IMAGE} (HAPI ${HAPI_VERSION})"
docker build \
  --build-arg "HAPI_VERSION=${HAPI_VERSION}" \
  -t "${FHIR_IMAGE}" \
  -f fhir-server/Dockerfile \
  fhir-server

echo
echo "Built: ${FHIR_IMAGE}"
echo
echo "Run the locally built image with:"
echo "  docker compose -f docker-compose.yml -f docker-compose.build.yml up -d"
