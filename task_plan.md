# Task Plan: Migrate privacyIDEA from MySQL to PostgreSQL (shared DB)

## Goal
Replace mariadb with a single postgres:16-alpine instance shared by privacyidea and pi-vpn-pooler.

## Phases
- [x] Phase 1: Research — understand current DB config in Dockerfile, entrypoint, pi.cfg, env files
- [x] Phase 2: Update docker-compose — replace mariadb with single postgres, remove vpn_pooler_db
- [x] Phase 3: Update environment files — change DB_API, DB_PORT, remove DB_EXTRA_PARAMS
- [x] Phase 4: Create init-vpn-pooler-db.sh — postgres init script for second database
- [x] Phase 5: Update build-images.sh — remove mariadb, single postgres
- [x] Phase 6: Update Makefile — fix volume names in distclean
- [x] Phase 7: Verify config validity

## Decisions Made
- Single postgres:16-alpine for both privacyidea (DB: pi) and vpn_pooler (DB: vpn_pooler)
- Init script /docker-entrypoint-initdb.d/init-vpn-pooler-db.sh creates second DB on first start
- psycopg2-binary already present in Dockerfile (line 29) — no Dockerfile changes needed
- DB_API changed from mysql+pymysql to postgresql+psycopg2
- DB_EXTRA_PARAMS removed (charset=utf8 is mysql-specific)
- Profile vpn_pooler added to db service

## Status
**DONE** — All phases completed and validated with `docker compose config`
