#!/usr/bin/env bash
# Run the daily maintenance tasks Decidim 0.26 expects (see "Scheduled tasks"
# in the Decidim install guide). Meant to be run from cron once a day, e.g.:
#
#   0 3 * * * /path/to/fundaction/scripts/daily_chores.sh >> /path/to/fundaction/log/daily_chores.log 2>&1
#
# Usage:
#   scripts/daily_chores.sh [options]
#
# Options:
#   -e, --env-file FILE   Source FILE before running (production env vars).
#                         Default: .rbenv-vars in the project root, if present
#   -h, --help            Show this help
#
# RAILS_ENV defaults to production. metrics:all and open_data:export only
# enqueue jobs, so the delayed_job worker must be running for them to finish.
# A failing task is reported but does not stop the others; the script exits 1
# if any task failed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.rbenv-vars"

usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -e|--env-file) ENV_FILE="$2"; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -f "$ENV_FILE" ]]; then
  # Export every KEY=VALUE line (works for .rbenv-vars and shell env files).
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi
export RAILS_ENV="${RAILS_ENV:-production}"

# cron runs with a minimal PATH; make rbenv's ruby and bundle available.
RBENV_ROOT="${RBENV_ROOT:-$HOME/.rbenv}"
if [[ -d "$RBENV_ROOT" ]]; then
  export PATH="$RBENV_ROOT/shims:$RBENV_ROOT/bin:$PATH"
fi

cd "$PROJECT_ROOT" || exit 1

TASKS=(
  "decidim:delete_data_portability_files"     # remove expired "download my data" files
  "decidim:metrics:all"                       # compute stats shown on the homepage/metrics page
  "decidim:open_data:export"                  # regenerate the open data download
  "decidim_meetings:clean_registration_forms" # remove forms of meetings that ended long ago
)

failed=0
for task in "${TASKS[@]}"; do
  echo "==> $(date '+%F %T') $task"
  if ! bundle exec rake "$task"; then
    echo "!! $task failed" >&2
    failed=1
  fi
done
echo "==> $(date '+%F %T') done"
exit "$failed"
