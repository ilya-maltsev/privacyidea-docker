#!/bin/bash
set -e

# Create a separate database and user for the VPN Pooler application
# inside the shared PostgreSQL instance.
# This script runs only on first container start (empty data directory).

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE USER ${VPN_POOLER_DB_USER} WITH PASSWORD '${VPN_POOLER_DB_PASSWORD}';
    CREATE DATABASE ${VPN_POOLER_DB_NAME} OWNER ${VPN_POOLER_DB_USER};
EOSQL
