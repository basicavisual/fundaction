#!/usr/bin/env bash
# Dump a PostgreSQL database from a remote server into a local file.
#
# Usage:
#   scripts/db_pull.sh [options]
#
# Options:
#   -H, --host HOST       SSH host or alias of the server (required)
#   -d, --db NAME         Remote database name (default: fundaction_production)
#   -U, --db-user USER    Remote database user (default: server's default role)
#       --db-host HOST    Remote database host, as seen from the server
#                         (default: local socket)
#       --db-port PORT    Remote database port (default: 5432)
#   -p, --password        Prompt for the remote database password. Without it,
#                         the server must allow access via peer auth or ~/.pgpass
#   -o, --output DIR      Local directory for the dump (default: db/dumps)
#   -r, --restore         After downloading, restore into the local development
#                         database (drops and recreates it; asks first)
#   -h, --help            Show this help
#
# Defaults can also be set in scripts/db_pull.env (not committed), e.g.:
#   REMOTE_HOST=myserver
#   REMOTE_DB=fundaction_production
#   REMOTE_DB_USER=fundaction
#
# The dump runs with the server's own pg_dump (custom format) and is streamed
# over SSH, so nothing is written to disk on the server.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

REMOTE_HOST=""
REMOTE_DB="fundaction_production"
REMOTE_DB_USER=""
REMOTE_DB_HOST=""
REMOTE_DB_PORT="5432"
OUT_DIR="$PROJECT_ROOT/db/dumps"
ASK_PASSWORD=false
RESTORE=false

# Local, uncommitted defaults.
if [[ -f "$SCRIPT_DIR/db_pull.env" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/db_pull.env"
fi

usage() { sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -H|--host)     REMOTE_HOST="$2"; shift 2 ;;
    -d|--db)       REMOTE_DB="$2"; shift 2 ;;
    -U|--db-user)  REMOTE_DB_USER="$2"; shift 2 ;;
    --db-host)     REMOTE_DB_HOST="$2"; shift 2 ;;
    --db-port)     REMOTE_DB_PORT="$2"; shift 2 ;;
    -p|--password) ASK_PASSWORD=true; shift ;;
    -o|--output)   OUT_DIR="$2"; shift 2 ;;
    -r|--restore)  RESTORE=true; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$REMOTE_HOST" ]]; then
  echo "Missing --host (or REMOTE_HOST in scripts/db_pull.env)." >&2
  exit 1
fi

REMOTE_DB_PASSWORD=""
if [[ "$ASK_PASSWORD" == true ]]; then
  read -r -s -p "Password for remote database user '${REMOTE_DB_USER:-default}': " REMOTE_DB_PASSWORD
  echo >&2
fi

mkdir -p "$OUT_DIR"
DUMP_FILE="$OUT_DIR/${REMOTE_DB}_$(date +%Y%m%d_%H%M%S).dump"
PARTIAL="$DUMP_FILE.partial"
trap 'rm -f "$PARTIAL"' EXIT

echo "==> Dumping '$REMOTE_DB' from '$REMOTE_HOST'..." >&2

# Build the remote script. Values are quoted with printf %q and sent over
# stdin, so the password never appears in a command line on either machine.
{
  echo "set -euo pipefail"
  printf 'export PGDATABASE=%q PGPORT=%q\n' "$REMOTE_DB" "$REMOTE_DB_PORT"
  [[ -n "$REMOTE_DB_USER" ]]     && printf 'export PGUSER=%q\n' "$REMOTE_DB_USER"
  [[ -n "$REMOTE_DB_HOST" ]]     && printf 'export PGHOST=%q\n' "$REMOTE_DB_HOST"
  [[ -n "$REMOTE_DB_PASSWORD" ]] && printf 'export PGPASSWORD=%q\n' "$REMOTE_DB_PASSWORD"
  echo "pg_dump --format=custom --no-owner --no-acl"
} | ssh "$REMOTE_HOST" "bash -s" > "$PARTIAL"

if [[ ! -s "$PARTIAL" ]]; then
  echo "!! Dump is empty, something went wrong." >&2
  exit 1
fi
# Make sure the file is a readable archive before keeping it.
pg_restore --list "$PARTIAL" > /dev/null

mv "$PARTIAL" "$DUMP_FILE"
trap - EXIT
echo "==> Saved $(du -h "$DUMP_FILE" | cut -f1) to $DUMP_FILE" >&2

if [[ "$RESTORE" == true ]]; then
  "$PROJECT_ROOT/scripts/db_restore.sh" "$DUMP_FILE"
fi
