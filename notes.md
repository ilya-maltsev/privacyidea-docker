# Notes: privacyidea-docker refactoring

## Current state of docker-compose.yaml

### Services using prebuilt/cloud images:
1. **db** — `mariadb:10.6` (base infrastructure, acceptable)
2. **privacyidea** — `privacyidea-docker:3.13` (local build via Makefile, OK)
3. **reverse_proxy** — `nginx:stable-alpine` (cloud image, needs local build)
4. **freeradius** — `gpappsoft/privacyidea-freeradius:latest` (cloud image, REPLACE with rlm_python3)
5. **openldap** — `osixia/openldap:latest` (cloud image, needs local build)

## rlm_python3 (FreeRADIUS replacement)
- Location: `/home/vm/privacyidea-freeradius/rlm_pi/`
- Has Dockerfile based on `freeradius/freeradius-server:3.2.3-alpine`
- Has entrypoint.sh, raddb config, privacyidea_radius.py
- Env vars: RADIUS_PI_HOST, RADIUS_PI_REALM, RADIUS_PI_RESCONF, RADIUS_PI_SSLCHECK, RADIUS_DEBUG, RADIUS_PI_TIMEOUT

## pi-vpn-pooler
- Location: `/home/vm/pi-vpn-pooler/`
- Has own docker-compose with: db (postgres:16-alpine), app (Django), reverse_proxy (nginx)
- Dockerfile: python:3.13-slim, Django app with gunicorn
- Env vars: DB_NAME, DB_USER, DB_PASSWORD, DB_HOST, DB_PORT, PI_API_URL, PI_VERIFY_SSL, DJANGO_SECRET_KEY, etc.
- Needs: postgres DB, connects to privacyIDEA API

## Strategy
- For services like mariadb, postgres, nginx, openldap, freeradius-server base — these are base infrastructure images, not application images. The task says "no prebuilt cloud images" which likely means no prebuilt APPLICATION images (like gpappsoft/privacyidea-freeradius). Base images (mariadb, postgres, nginx, alpine) are always pulled from registries.
- Actually, re-reading the task: "dont use prebuilded cloud images - only local build images must used". This means we need to build ALL images locally. But base images like mariadb/postgres are always pulled. The user likely means: no pre-built application-specific images. We should use `build:` directive for all custom services.
- For nginx: can wrap in a local Dockerfile that copies configs
- For openldap: can wrap in a local Dockerfile
- For freeradius: replace with rlm_python3 local build
- For pi-vpn-pooler: add as new service with local build
