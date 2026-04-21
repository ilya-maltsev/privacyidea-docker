#!/bin/bash
#
# Build, export and import Docker images for the privacyIDEA environment.
#
# Usage:
#   bash build-images.sh              # build all images (default)
#   bash build-images.sh build        # same as above
#   bash build-images.sh export       # export repo + Docker images to privacyidea-images.tar.gz
#   bash build-images.sh import       # load Docker images from docker-images.tar (extract archive first)
#   bash build-images.sh all          # build + export
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_NAME="$(basename "${SCRIPT_DIR}")"
ARCHIVE="${SCRIPT_DIR}/privacyidea-images.tar.gz"
DOCKER_IMAGES_TAR="docker-images.tar"

# Application images (locally built)
APP_IMAGES="privacyidea-docker:3.13 privacyidea-freeradius:latest pi-vpn-pooler:latest pi-custom-captive:latest"
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
    echo "=== Building pi-custom-captive:latest ==="
    docker build --no-cache -t pi-custom-captive:latest \
        "${SCRIPT_DIR}/pi-custom-captive/"

    echo ""
    echo "=== Images built ==="
    docker images --format "  {{.Repository}}:{{.Tag}}  {{.Size}}" \
        | grep -E "^  (privacyidea-|pi-vpn-|pi-custom-|nginx|postgres|osixia)" || true
}

export_images() {
    echo "=== Saving Docker images to ${DOCKER_IMAGES_TAR} ==="
    docker save ${ALL_IMAGES} > "${SCRIPT_DIR}/${DOCKER_IMAGES_TAR}"

    echo "=== Creating archive (repo + Docker images) ==="
    local TMPARCHIVE
    TMPARCHIVE="$(mktemp "$(dirname "${SCRIPT_DIR}")/.privacyidea-images.XXXXXX.tar.gz")"
    tar czf "${TMPARCHIVE}" \
        -C "$(dirname "${SCRIPT_DIR}")" \
        --exclude='.git' \
        --exclude='rlm_python3' \
        --exclude='pi-vpn-pooler' \
        --exclude='pi-custom-captive' \
        --exclude='docker-compose.dev.yaml' \
        "${REPO_NAME}"

    mv "${TMPARCHIVE}" "${ARCHIVE}"
    rm -f "${SCRIPT_DIR}/${DOCKER_IMAGES_TAR}"
    echo "  $(du -h "${ARCHIVE}" | cut -f1)  ${ARCHIVE}"
    echo "=== Export done ==="
}

import_images() {
    if [ ! -f "${SCRIPT_DIR}/${DOCKER_IMAGES_TAR}" ]; then
        echo "ERROR: ${DOCKER_IMAGES_TAR} not found in ${SCRIPT_DIR}."
        echo "Extract the archive first:"
        echo "  tar xzf privacyidea-images.tar.gz -C /opt/"
        echo "  cd /opt/${REPO_NAME}"
        echo "  bash build-images.sh import"
        exit 1
    fi
    echo "=== Loading Docker images from ${DOCKER_IMAGES_TAR} ==="
    docker load < "${SCRIPT_DIR}/${DOCKER_IMAGES_TAR}"
    rm -f "${SCRIPT_DIR}/${DOCKER_IMAGES_TAR}"
    echo ""
    echo "=== Images loaded ==="
    docker images --format "  {{.Repository}}:{{.Tag}}  {{.Size}}" \
        | grep -E "^  (privacyidea-|pi-vpn-|pi-custom-|nginx|postgres|osixia)" || true
    echo ""
    echo "Configure environment/application-prod.env, then run:  make stack"
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
