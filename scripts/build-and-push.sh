#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Load docker/.env when present so GHCR vars can be kept out of shell profile
ENV_FILE="$REPO_ROOT/docker/.env"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

# GHCR_USERNAME must be set
if [[ -z "${GHCR_USERNAME:-}" ]]; then
    echo "ERROR: GHCR_USERNAME environment variable is not set"
    echo "Set it in docker/.env or your shell profile"
    exit 1
fi

# GHCR_TOKEN must be set
if [[ -z "${GHCR_TOKEN:-}" ]]; then
    echo "ERROR: GHCR_TOKEN environment variable is not set"
    echo "Set it in docker/.env or your shell profile"
    exit 1
fi

GHCR_PREFIX="ghcr.io/${GHCR_USERNAME}/openclaw-docker-config"
TAG="${1:-latest}"
SHA=$(git -C "$REPO_ROOT" rev-parse --short HEAD)

echo "==> Logging in to GHCR as $GHCR_USERNAME ..."
if ! echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USERNAME" --password-stdin >/dev/null; then
    echo "ERROR: Docker login to ghcr.io failed"
    echo "Verify GHCR_USERNAME, GHCR_TOKEN and token scope (write:packages)"
    exit 1
fi
echo "✓ GHCR login successful"
echo ""

echo "==> Validating config ..."
"$REPO_ROOT/scripts/validate-config.sh"
echo ""
"$REPO_ROOT/scripts/check-secrets.sh"
echo ""

# --- Gateway image ---
GW_IMAGE="$GHCR_PREFIX/openclaw-gateway"
echo "==> Building gateway image ..."
echo "    Image: $GW_IMAGE"
echo "    Tags:  $TAG, $SHA"
echo ""

docker buildx build --platform linux/amd64 -f "$REPO_ROOT/docker/Dockerfile" -t "$GW_IMAGE:$TAG" -t "$GW_IMAGE:$SHA" --push "$REPO_ROOT"

echo ""
echo "✓ Built and pushed $GW_IMAGE:$TAG (linux/amd64)"
echo "✓ Built and pushed $GW_IMAGE:$SHA (linux/amd64)"

# --- Workspace-sync image ---
WS_IMAGE="$GHCR_PREFIX/workspace-sync"
echo ""
echo "==> Building workspace-sync image ..."
echo "    Image: $WS_IMAGE"
echo "    Tags:  $TAG, $SHA"
echo ""

docker buildx build --platform linux/amd64 -f "$REPO_ROOT/docker/workspace-sync/Dockerfile" -t "$WS_IMAGE:$TAG" -t "$WS_IMAGE:$SHA" --push "$REPO_ROOT/docker/workspace-sync"

echo ""
echo "✓ Built and pushed $WS_IMAGE:$TAG (linux/amd64)"
echo "✓ Built and pushed $WS_IMAGE:$SHA (linux/amd64)"
