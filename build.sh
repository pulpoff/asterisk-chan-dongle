#!/bin/bash
###############################################################################
# build.sh — Build & push multi-arch Docker images for asterisk-chan-dongle
#
# Prerequisites:
#   - Docker with buildx support (Docker Desktop or Docker CE 19.03+)
#   - QEMU user-static (for cross-compilation)
#   - Logged in to GHCR: docker login ghcr.io -u YOUR_GITHUB_USER
#
# Usage:
#   ./build.sh              # Build + push all 3 architectures
#   ./build.sh --local      # Build for current arch only (for testing)
#   ./build.sh --no-push    # Build all arches but don't push
###############################################################################
set -e

IMAGE="ghcr.io/pulpoff/asterisk-chan-dongle"
TAG="latest"
PLATFORMS="linux/amd64,linux/arm64,linux/arm/v7"
PUSH=true
LOCAL=false

for arg in "$@"; do
    case $arg in
        --local)   LOCAL=true; PUSH=false ;;
        --no-push) PUSH=false ;;
        --help|-h)
            echo "Usage: $0 [--local] [--no-push]"
            echo "  --local    Build for current architecture only (fast, for testing)"
            echo "  --no-push  Build all architectures but don't push to registry"
            exit 0
            ;;
    esac
done

echo "============================================================"
echo "  Asterisk 20 LTS + chan_dongle — Docker Multi-Arch Build"
echo "============================================================"
echo ""

# ── Ensure buildx builder exists ───────────────────────────────────────────
BUILDER_NAME="dongle-multiarch"
if ! docker buildx inspect "$BUILDER_NAME" &>/dev/null; then
    echo ">> Creating buildx builder with QEMU support..."
    docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
    docker buildx create --name "$BUILDER_NAME" --use --driver docker-container
    docker buildx inspect --bootstrap "$BUILDER_NAME"
else
    echo ">> Using existing buildx builder: $BUILDER_NAME"
    docker buildx use "$BUILDER_NAME"
fi

echo ""

# ── Build ──────────────────────────────────────────────────────────────────
if [ "$LOCAL" = true ]; then
    echo ">> Building for current architecture only (local test)..."
    docker buildx build \
        --tag "${IMAGE}:${TAG}" \
        --load \
        .
    echo ""
    echo ">> Local image built: ${IMAGE}:${TAG}"
    echo "   Test it with:"
    echo "     docker run --rm --privileged -v /dev/bus/usb:/dev/bus/usb \\"
    echo "       -e TRUNK_PROTO=iax -e TRUNK_USER=test -e TRUNK_PASS=test \\"
    echo "       -e TRUNK_HOST=localhost ${IMAGE}:${TAG}"
else
    if [ "$PUSH" = true ]; then
        echo ">> Building for: $PLATFORMS"
        echo ">> Pushing to: ${IMAGE}:${TAG}"
        echo ""
        echo "   (This will take a while — ARM builds run under QEMU emulation)"
        echo ""
        docker buildx build \
            --platform "$PLATFORMS" \
            --tag "${IMAGE}:${TAG}" \
            --push \
            .
        echo ""
        echo ">> Done! Image pushed: ${IMAGE}:${TAG}"
        echo "   Users can now pull with: docker pull ${IMAGE}:${TAG}"
    else
        echo ">> Building for: $PLATFORMS (no push)"
        echo ""
        docker buildx build \
            --platform "$PLATFORMS" \
            --tag "${IMAGE}:${TAG}" \
            .
        echo ""
        echo ">> Build complete (not pushed). Use without --no-push to push."
    fi
fi

echo ""
echo "============================================================"
echo "  Build finished!"
echo "============================================================"
