#!/usr/bin/env bash
# =============================================================================
#  docker/build.sh — build the suite's custom Frappe/ERPNext image
# -----------------------------------------------------------------------------
#  Usage:
#     ./docker/build.sh
#     IMAGE=myrepo/erp TAG=v1 FRAPPE_BRANCH=develop ./docker/build.sh
#
#  Requires Docker installed and running.
# =============================================================================
set -euo pipefail

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-shyberdev/jew-pawn-lending}"
TAG="${TAG:-latest}"
FRAPPE_BRANCH="${FRAPPE_BRANCH:-develop}"

command -v docker >/dev/null 2>&1 || { echo "Docker is not installed." >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker daemon is not running / no permission." >&2; exit 1; }

echo "==> Building $IMAGE:$TAG (base frappe/erpnext:$FRAPPE_BRANCH)"
docker build \
  --build-arg "FRAPPE_BRANCH=$FRAPPE_BRANCH" \
  -t "$IMAGE:$TAG" \
  -f "$BUNDLE_DIR/docker/Containerfile" \
  "$BUNDLE_DIR"

echo
echo "==> Built $IMAGE:$TAG"
echo "Next: run it with the frappe_docker compose stack — see docker/README.md"
