#!/usr/bin/env bash
# Applies the migration to a throwaway database on a running Postgres 15+ and
# runs the smoke test. Usage: PGHOST=... PGPORT=... bash run-local.sh
set -euo pipefail
cd "$(dirname "$0")"
db="ghostties_cloud_smoke_$$"
createdb "$db"
trap 'dropdb "$db"' EXIT
psql -qX -v ON_ERROR_STOP=1 -d "$db" -f stubs.sql
for f in ../migrations/*.sql; do psql -qX -v ON_ERROR_STOP=1 -d "$db" -f "$f"; done
psql -X -v ON_ERROR_STOP=1 -d "$db" -At -f smoke.sql
