#!/usr/bin/env bash
# Copy the Active Storage files (storage/) from the remote server into this
# local project.
#
# Usage:
#   scripts/storage_pull.sh [options]
#
# Options:
#   -H, --host HOST       SSH host or alias of the server (required)
#   -a, --app-dir DIR     Path of the app on the server, i.e. the directory that
#                         contains storage/ (required)
#       --delete          Delete local files that no longer exist on the server
#                         (exact mirror). Off by default
#   -n, --dry-run         Show what would be copied without copying anything
#   -h, --help            Show this help
#
# Defaults can be set in scripts/db_pull.env (shared with db_pull.sh), e.g.:
#   REMOTE_HOST=myserver
#   REMOTE_APP_DIR=/home/decidim/fundaction
#
# Uses rsync over SSH, so re-runs only transfer new or changed files.
# rsync must be installed on both machines.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

REMOTE_HOST=""
REMOTE_APP_DIR=""
DELETE=false
DRY_RUN=false

if [[ -f "$SCRIPT_DIR/db_pull.env" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/db_pull.env"
fi

usage() { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -H|--host)    REMOTE_HOST="$2"; shift 2 ;;
    -a|--app-dir) REMOTE_APP_DIR="$2"; shift 2 ;;
    --delete)     DELETE=true; shift ;;
    -n|--dry-run) DRY_RUN=true; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$REMOTE_HOST" || -z "$REMOTE_APP_DIR" ]]; then
  echo "Missing --host and/or --app-dir (or REMOTE_HOST / REMOTE_APP_DIR in scripts/db_pull.env)." >&2
  exit 1
fi
REMOTE_APP_DIR="${REMOTE_APP_DIR%/}"

RSYNC_OPTS=(--archive --compress --partial --human-readable --info=progress2,stats1)
[[ "$DELETE" == true ]]  && RSYNC_OPTS+=(--delete)
[[ "$DRY_RUN" == true ]] && RSYNC_OPTS+=(--dry-run --itemize-changes)

mkdir -p "$PROJECT_ROOT/storage"
echo "==> $REMOTE_HOST:$REMOTE_APP_DIR/storage/ -> storage/" >&2
# Trailing slashes: copy the directory's contents, not the directory itself.
rsync "${RSYNC_OPTS[@]}" -e ssh "$REMOTE_HOST:$REMOTE_APP_DIR/storage/" "$PROJECT_ROOT/storage/"

echo "==> Done." >&2
