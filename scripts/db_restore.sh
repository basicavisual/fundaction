#!/usr/bin/env bash
# Restore a pg_dump file (made by scripts/db_pull.sh) into the local
# development database, replacing what is there.
#
# Usage:
#   scripts/db_restore.sh [options] [DUMP_FILE]
#
# DUMP_FILE defaults to the newest *.dump in db/dumps/.
#
# Options:
#       --org-host HOST   Set the organization's host so it opens locally
#                         (default: localhost)
#       --keep-host       Leave the organization's host as it is in the dump
#   -m, --migrate         Run bin/rails db:migrate after restoring
#   -j, --jobs N          Parallel restore jobs (default: 4)
#   -y, --yes             Don't ask for confirmation before dropping the database
#   -h, --help            Show this help
#
# Local database settings come from .rbenv-vars (DATABASE_USERNAME,
# DATABASE_PASSWORD, and optionally DATABASE_HOST, DATABASE_PORT, DATABASE_NAME),
# the same values the app uses.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DUMP_FILE=""
ORG_HOST="localhost"
MIGRATE=false
JOBS=4
ASSUME_YES=false

usage() { sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org-host)   ORG_HOST="$2"; shift 2 ;;
    --keep-host)  ORG_HOST=""; shift ;;
    -m|--migrate) MIGRATE=true; shift ;;
    -j|--jobs)    JOBS="$2"; shift 2 ;;
    -y|--yes)     ASSUME_YES=true; shift ;;
    -h|--help)    usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    *)  DUMP_FILE="$1"; shift ;;
  esac
done

if [[ -z "$DUMP_FILE" ]]; then
  DUMP_FILE="$(ls -1t "$PROJECT_ROOT"/db/dumps/*.dump 2>/dev/null | head -1 || true)"
  if [[ -z "$DUMP_FILE" ]]; then
    echo "No dump file given and none found in db/dumps/. Run scripts/db_pull.sh first." >&2
    exit 1
  fi
fi
if [[ ! -f "$DUMP_FILE" ]]; then
  echo "Dump file not found: $DUMP_FILE" >&2
  exit 1
fi

# --- local connection settings (same as the app) ---
unset PGDATABASE PGUSER PGPASSWORD PGHOST PGPORT
if [[ -f "$PROJECT_ROOT/.rbenv-vars" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/.rbenv-vars"
  set +a
fi
export PGHOST="${DATABASE_HOST:-localhost}"
export PGPORT="${DATABASE_PORT:-5432}"
if [[ -n "${DATABASE_USERNAME:-}" ]]; then export PGUSER="$DATABASE_USERNAME"; fi
if [[ -n "${DATABASE_PASSWORD:-}" ]]; then export PGPASSWORD="$DATABASE_PASSWORD"; fi
LOCAL_DB="${DATABASE_NAME:-fundaction_development}"

echo "Dump:     $DUMP_FILE ($(du -h "$DUMP_FILE" | cut -f1))" >&2
echo "Target:   $LOCAL_DB on $PGHOST:$PGPORT as ${PGUSER:-$USER}" >&2

if [[ "$ASSUME_YES" != true ]]; then
  read -r -p "This will DROP and recreate '$LOCAL_DB'. Continue? [y/N] " answer
  if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    echo "Aborted." >&2
    exit 0
  fi
fi

# --- recreate and restore ---
echo "==> Recreating '$LOCAL_DB'..." >&2
# --force closes open connections (e.g. a running rails server or console).
dropdb --if-exists --force "$LOCAL_DB"
createdb "$LOCAL_DB"

echo "==> Restoring (this can take a while)..." >&2
# pg_restore exits non-zero even for harmless errors (e.g. extension comments
# it isn't allowed to set), so report them instead of stopping here.
if ! pg_restore --no-owner --no-acl --jobs="$JOBS" --dbname="$LOCAL_DB" "$DUMP_FILE"; then
  echo "!! pg_restore reported errors (see above). Often harmless; check before relying on the data." >&2
fi

# --- make it usable locally ---
if [[ -n "$ORG_HOST" ]]; then
  org_count="$(psql -d "$LOCAL_DB" -tAc "SELECT count(*) FROM decidim_organizations")"
  if [[ "$org_count" == "1" ]]; then
    old_host="$(psql -d "$LOCAL_DB" -tAc "SELECT host FROM decidim_organizations")"
    # psql only substitutes :'host' in SQL read from stdin/files, not with -c.
    psql -d "$LOCAL_DB" -q -v ON_ERROR_STOP=1 -v host="$ORG_HOST" \
      <<< "UPDATE decidim_organizations SET host = :'host';"
    echo "==> Organization host: $old_host -> $ORG_HOST" >&2
  else
    echo "!! Found $org_count organizations, not changing hosts. Set them yourself:" >&2
    psql -d "$LOCAL_DB" -c "SELECT id, host FROM decidim_organizations ORDER BY id" >&2
  fi
fi

cd "$PROJECT_ROOT"
# The dump is marked as a production database; without this, Rails refuses
# destructive tasks such as db:drop or db:schema:load.
echo "==> Marking database as development..." >&2
RAILS_ENV=development bin/rails db:environment:set

if [[ "$MIGRATE" == true ]]; then
  echo "==> Running pending migrations..." >&2
  RAILS_ENV=development bin/rails db:migrate
else
  echo "    Pending migrations (if any) were not run. Use --migrate, or: bin/rails db:migrate" >&2
fi

echo "==> Done. Restored $LOCAL_DB from $(basename "$DUMP_FILE")." >&2
