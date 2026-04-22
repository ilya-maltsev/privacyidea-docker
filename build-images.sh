#!/bin/bash
#
# Build, export and import Docker images for the privacyIDEA environment.
#
# Usage:
#   bash build-images.sh              # build all images (default)
#   bash build-images.sh build        # same as above
#   bash build-images.sh build captive pooler   # build only selected images
#   bash build-images.sh export                 # export all images + repo
#   bash build-images.sh export captive         # export only selected images + repo
#   bash build-images.sh import                 # load all images from archive
#   bash build-images.sh import captive pooler  # load only selected images
#   bash build-images.sh all                    # build + export
#   bash build-images.sh all captive            # build + export selected
#
# Short names:
#   privacyidea (pi), freeradius (radius), pooler (vpn_pooler),
#   captive, postgres, nginx, openldap (ldap)
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

# --- Selection helpers --------------------------------------------------------

resolve_image() {
    case "$1" in
        privacyidea|pi)    echo "privacyidea-docker:3.13" ;;
        freeradius|radius)  echo "privacyidea-freeradius:latest" ;;
        pooler|vpn_pooler)  echo "pi-vpn-pooler:latest" ;;
        captive)            echo "pi-custom-captive:latest" ;;
        postgres)           echo "postgres:16-alpine" ;;
        nginx)              echo "nginx:stable-alpine" ;;
        openldap|ldap)      echo "osixia/openldap:latest" ;;
        *) echo "" ;;
    esac
}

SELECTED=()

parse_selection() {
    for name in "$@"; do
        local full
        full=$(resolve_image "$name")
        if [ -z "$full" ]; then
            echo "ERROR: Unknown image name: $name"
            echo "Available: privacyidea (pi), freeradius (radius), pooler (vpn_pooler),"
            echo "           captive, postgres, nginx, openldap (ldap)"
            exit 1
        fi
        SELECTED+=("$full")
    done
}

# Return 0 if image is selected (or no selection = all).
is_selected() {
    local img="$1"
    [ ${#SELECTED[@]} -eq 0 ] && return 0
    for s in "${SELECTED[@]}"; do
        [ "$s" = "$img" ] && return 0
    done
    return 1
}

# Build space-separated list of selected images (for docker save/load).
selected_images_list() {
    if [ ${#SELECTED[@]} -eq 0 ]; then
        echo "${ALL_IMAGES}"
    else
        echo "${SELECTED[*]}"
    fi
}

show_help() {
    cat <<'EOF'
Usage: build-images.sh <command> [image ...]

Commands:
  build    Build Docker images (default if no command given)
  export   Save Docker images + repo to privacyidea-images.tar.gz
  import   Load Docker images from archive (extract archive first)
  all      Build + export
  help     Show this help

Image short names (optional — omit to operate on all):
  privacyidea  (pi)          privacyidea-docker:3.13
  freeradius   (radius)      privacyidea-freeradius:latest
  pooler       (vpn_pooler)  pi-vpn-pooler:latest
  captive                    pi-custom-captive:latest
  postgres                   postgres:16-alpine
  nginx                      nginx:stable-alpine
  openldap     (ldap)        osixia/openldap:latest

Examples:
  bash build-images.sh                        # build all
  bash build-images.sh build captive pooler   # build only captive + vpn_pooler
  bash build-images.sh export pi radius       # export selected images + repo
  bash build-images.sh all captive            # build + export captive only
EOF
}

# --- Core functions -----------------------------------------------------------

pull_infra() {
    for img in ${INFRA_IMAGES}; do
        if is_selected "$img"; then
            echo ""
            echo "--- Pulling ${img} ---"
            docker pull "${img}"
        fi
    done
}

init_submodules() {
    echo "=== Initializing git submodules ==="
    git -C "${SCRIPT_DIR}" submodule update --init --recursive
}

build_images() {
    init_submodules
    pull_infra

    if is_selected "privacyidea-docker:3.13"; then
        echo ""
        echo "=== Building privacyidea-docker:3.13 ==="
        docker build --no-cache -t privacyidea-docker:3.13 \
            --build-arg PI_VERSION=3.13 \
            --build-arg PI_VERSION_BUILD=3.13 \
            "${SCRIPT_DIR}/"
    fi

    if is_selected "privacyidea-freeradius:latest"; then
        echo ""
        echo "=== Building privacyidea-freeradius:latest ==="
        docker build --no-cache -t privacyidea-freeradius:latest \
            "${SCRIPT_DIR}/rlm_python3/"
    fi

    if is_selected "pi-vpn-pooler:latest"; then
        echo ""
        echo "=== Building pi-vpn-pooler:latest ==="
        docker build --no-cache -t pi-vpn-pooler:latest \
            "${SCRIPT_DIR}/pi-vpn-pooler/"
    fi

    if is_selected "pi-custom-captive:latest"; then
        echo ""
        echo "=== Building pi-custom-captive:latest ==="
        docker build --no-cache -t pi-custom-captive:latest \
            "${SCRIPT_DIR}/pi-custom-captive/"
    fi

    echo ""
    echo "=== Images built ==="
    docker images --format "  {{.Repository}}:{{.Tag}}  {{.Size}}" \
        | grep -E "^  (privacyidea-|pi-vpn-|pi-custom-|nginx|postgres|osixia)" || true
}

export_images() {
    local IMAGES
    IMAGES="$(selected_images_list)"
    echo "=== Saving Docker images to ${DOCKER_IMAGES_TAR} ==="
    echo "  images: ${IMAGES}"
    docker save ${IMAGES} > "${SCRIPT_DIR}/${DOCKER_IMAGES_TAR}"

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
        --exclude='privacyidea-images.tar.gz' \
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
shift 2>/dev/null || true
parse_selection "$@"

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
    help|-h|--help)
        show_help
        ;;
    *)
        echo "Unknown command: ${CMD}"
        echo ""
        show_help
        exit 1
        ;;
esac
