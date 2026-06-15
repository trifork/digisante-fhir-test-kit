#!/usr/bin/env bash
# Local test entrypoint: run the test kit inside a multipass VM using podman.
#
# Ensures a multipass VM exists (creating it and installing podman +
# podman-compose if not), mounts this repository into the VM, then runs the same
# provision + test scripts that CI runs.
#
#   VM_NAME   multipass instance name (default: fhir-test-kit)
set -euo pipefail

VM="${VM_NAME:-fhir-test-kit}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MOUNT="/home/ubuntu/app"

if ! command -v multipass >/dev/null 2>&1; then
  echo "ERROR: multipass is not installed. See https://multipass.run/install" >&2
  exit 1
fi

if multipass info "$VM" >/dev/null 2>&1; then
  echo "Using existing multipass VM: $VM"
  multipass start "$VM" >/dev/null 2>&1 || true
else
  echo "Creating multipass VM: $VM"
  multipass launch --name "$VM" --cpus 2 --memory 4G --disk 20G 22.04
  echo "Installing podman + podman-compose in $VM"
  multipass exec "$VM" -- sudo apt-get update -y
  multipass exec "$VM" -- sudo apt-get install -y podman python3-pip curl
  multipass exec "$VM" -- sudo pip3 install podman-compose
fi

# Mount the repo (idempotent — ignore "already mounted").
multipass mount "$REPO_DIR" "$VM:$MOUNT" 2>/dev/null || true

echo "Running provision + tests inside $VM"
multipass exec "$VM" -- bash -lc "cd $MOUNT && COMPOSE='podman-compose' ./tests/provision.sh && ./tests/run-tests.sh"
status=$?

echo
echo "To inspect logs:   multipass exec $VM -- bash -lc 'cd $MOUNT && podman-compose logs --tail=100'"
echo "To tear down:      multipass delete $VM && multipass purge"
exit $status
