#!/usr/bin/env bash
set -euo pipefail

# Build the DigiSanté FHIR Test Kit images.
#
# The selected HAPI FHIR version is baked into the image NAME, while the kit's
# own release is carried as a separate image TAG (IMAGE_VERSION). Both are
# configurable; defaults below (and any values in a local .env) are used when
# unset.

cd "$(dirname "$0")"

# Load .env if present (without clobbering values already in the environment).
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

HAPI_VERSION="${HAPI_VERSION:-v8.4.0-3}"
IMAGE_VERSION="${IMAGE_VERSION:-0.1.0}"
IMAGE_PREFIX="${IMAGE_PREFIX:-digisante-fhir-test-kit}"

FHIR_IMAGE="${IMAGE_PREFIX}-hapi-${HAPI_VERSION}:${IMAGE_VERSION}"

echo "Building FHIR server image: ${FHIR_IMAGE} (HAPI ${HAPI_VERSION})"
docker build \
  --build-arg "HAPI_VERSION=${HAPI_VERSION}" \
  -t "${FHIR_IMAGE}" \
  -f fhir-server/Dockerfile \
  fhir-server

echo
echo "Built:"
echo "  ${FHIR_IMAGE}"
echo
echo "Run with: HAPI_VERSION=${HAPI_VERSION} IMAGE_VERSION=${IMAGE_VERSION} docker compose up -d"
