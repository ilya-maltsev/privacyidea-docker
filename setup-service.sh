#!/bin/bash
#
# Set up the privacyIDEA Docker stack as a non-root systemd service.
#
# Creates the service user if it does not exist, adds it to the docker group,
# grants ownership of the working directory, and installs the systemd unit.
#
# Usage:
#   sudo bash setup-service.sh [USER] [WORKDIR]
#
# Defaults:
#   USER    = privacyidea
#   WORKDIR = directory containing this script
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SERVICE_USER="${1:-privacyidea}"
SERVICE_WORKDIR="${2:-${SCRIPT_DIR}}"
SERVICE_NAME="privacyidea-docker"
SERVICE_TEMPLATE="${SERVICE_WORKDIR}/templates/privacyidea-docker.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root."
    echo "Usage: sudo bash setup-service.sh [USER] [WORKDIR]"
    exit 1
fi

if [ ! -f "${SERVICE_TEMPLATE}" ]; then
    echo "ERROR: Service template not found: ${SERVICE_TEMPLATE}"
    exit 1
fi

# --- Create user if it does not exist ---
if id "${SERVICE_USER}" &>/dev/null; then
    echo "User '${SERVICE_USER}' already exists."
else
    echo "Creating system user: ${SERVICE_USER}"
    useradd --system --no-create-home --shell /usr/sbin/nologin "${SERVICE_USER}"
fi

# --- Add user to docker group ---
if groups "${SERVICE_USER}" 2>/dev/null | grep -q '\bdocker\b'; then
    echo "User '${SERVICE_USER}' is already in the docker group."
else
    echo "Adding '${SERVICE_USER}' to the docker group."
    usermod -aG docker "${SERVICE_USER}"
fi

# --- Create data directories ---
DATA_DIRS="pgdata pidata vpn_pooler_static vpn_pooler_data captive_static rsyslog_logs"
echo "Creating data directories under ${SERVICE_WORKDIR}/data/"
for d in ${DATA_DIRS}; do
    mkdir -p "${SERVICE_WORKDIR}/data/${d}"
done

# --- Set ownership of working directory ---
echo "Setting ownership of ${SERVICE_WORKDIR} to ${SERVICE_USER}"
chown -R "${SERVICE_USER}:" "${SERVICE_WORKDIR}"

# --- Install systemd service ---
echo "Installing systemd service: ${SERVICE_NAME}"
sed -e "s|__USER__|${SERVICE_USER}|g" \
    -e "s|__WORKDIR__|${SERVICE_WORKDIR}|g" \
    "${SERVICE_TEMPLATE}" > "${SERVICE_FILE}"

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}.service"

echo ""
echo "Done."
echo "  User:    ${SERVICE_USER}"
echo "  WorkDir: ${SERVICE_WORKDIR}"
echo "  Start:   sudo systemctl start ${SERVICE_NAME}"
echo "  Stop:    sudo systemctl stop ${SERVICE_NAME}"
echo "  Status:  sudo systemctl status ${SERVICE_NAME}"
echo "  Logs:    sudo journalctl -u ${SERVICE_NAME}"
