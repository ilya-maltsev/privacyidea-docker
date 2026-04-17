#!/bin/bash
#
# Build, export and import Docker images for the privacyIDEA environment.
#
# Usage:
#   bash build-images.sh              # build all images (default)
#   bash build-images.sh build        # same as above
#   bash build-images.sh export       # export to privacyidea-images.tar.gz
#   bash build-images.sh import       # import from privacyidea-images.tar.gz
#   bash build-images.sh all          # build + export
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCHIVE="${SCRIPT_DIR}/privacyidea-images.tar.gz"

# Application images (locally built)
APP_IMAGES="privacyidea-docker:3.13 privacyidea-freeradius:latest pi-vpn-pooler:latest"
# Infrastructure images (pulled from registry)
INFRA_IMAGES="postgres:16-alpine nginx:stable-alpine osixia/openldap:latest"
# All images for export/import
ALL_IMAGES="${APP_IMAGES} ${INFRA_IMAGES}"

pull_infra() {
    echo "=== Pulling infrastructure images ==="
    for img in ${INFRA_IMAGES}; do
        echo ""
        echo "--- Pulling ${img} ---"
        docker pull "${img}"
    done
}

init_submodules() {
    echo "=== Initializing git submodules ==="
    git -C "${SCRIPT_DIR}" submodule update --init --recursive
}

build_images() {
    init_submodules
    pull_infra

    echo ""
    echo "=== Building privacyidea-docker:3.13 ==="
    docker build --no-cache -t privacyidea-docker:3.13 \
        --build-arg PI_VERSION=3.13 \
        --build-arg PI_VERSION_BUILD=3.13 \
        "${SCRIPT_DIR}/"

    echo ""
    echo "=== Building privacyidea-freeradius:latest ==="
    docker build --no-cache -t privacyidea-freeradius:latest \
        "${SCRIPT_DIR}/rlm_python3/"

    echo ""
    echo "=== Building pi-vpn-pooler:latest ==="
    docker build --no-cache -t pi-vpn-pooler:latest \
        "${SCRIPT_DIR}/pi-vpn-pooler/"

    echo ""
    echo "=== Images built ==="
    docker images --format "  {{.Repository}}:{{.Tag}}  {{.Size}}" \
        | grep -E "^  (privacyidea-|pi-vpn-|nginx|postgres|osixia)" || true
}

export_images() {
    echo "=== Exporting images to ${ARCHIVE} ==="
    docker save ${ALL_IMAGES} | gzip > "${ARCHIVE}"
    echo "  $(du -h "${ARCHIVE}" | cut -f1)  ${ARCHIVE}"
    echo "=== Export done ==="
}

import_images() {
    if [ ! -f "${ARCHIVE}" ]; then
        echo "ERROR: ${ARCHIVE} not found."
        echo "Run '$(basename "$0") export' first or copy the archive here."
        exit 1
    fi
    echo "=== Importing images from ${ARCHIVE} ==="
    gunzip -c "${ARCHIVE}" | docker load
    echo ""
    echo "=== Images loaded ==="
    docker images --format "  {{.Repository}}:{{.Tag}}  {{.Size}}" \
        | grep -E "^  (privacyidea-|pi-vpn-|nginx|postgres|osixia)" || true
    echo ""
    echo "Now run:  docker compose --profile=fullstack up -d"
}

CMD="${1:-build}"

case "${CMD}" in
    build)
        build_images
        ;;
    export)
        export_images
        ;;
    import)
        import_images
        ;;
    all)
        build_images
        echo ""
        export_images
        ;;
    *)
        echo "Usage: $(basename "$0") {build|export|import|all}"
        exit 1
        ;;
esac
