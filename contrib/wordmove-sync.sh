#!/usr/bin/env bash
#
# Run a wordmove-ng sync from cron (or any non interactive context).
#
# Copy this file somewhere in your PATH, adjust the settings block or override
# the variables from the environment, then add a crontab entry such as
#
#   MAILTO=you@example.com
#   30 2 * * * /usr/local/bin/wordmove-sync.sh
#
# Cron provides almost no environment: no rvm/rbenv shims, no ssh-agent, no TTY.
# This script makes ruby and the peer tools findable, relies on a key that
# needs no passphrase (see the docs page "Automation"), refuses to overlap
# with a still-running sync, and writes a plain-text log per run.
#
# Test it the way cron will run it before trusting the schedule:
#   env -i HOME=$HOME SHELL=/bin/bash PATH=/usr/bin:/bin /usr/local/bin/wordmove-sync.sh
set -euo pipefail

# ---- settings (override with environment variables) --------------------------
SITE_DIR="${SITE_DIR:-/path/to/wordpress}"        # directory holding movefile.yml
ENVIRONMENT="${ENVIRONMENT:-production}"          # remote environment (-e)
ACTION="${ACTION:-pull}"                          # pull or push
COMPONENTS="${COMPONENTS:---all --no-db}"         # component flags
LOG_DIR="${LOG_DIR:-$HOME/log/wordmove}"
KEEP_LOGS="${KEEP_LOGS:-30}"                      # how many run logs to keep
RUBY_VERSION="${RUBY_VERSION:-}"                  # e.g. ruby-3.4.9 for rvm; empty = whatever is on PATH
# -----------------------------------------------------------------------------

case "$ACTION" in
  pull|push) ;;
  *) echo "ACTION must be pull or push, got '$ACTION'" >&2; exit 2 ;;
esac

# Ruby version managers are not loaded by cron.
if [ -n "$RUBY_VERSION" ] && [ -s "$HOME/.rvm/scripts/rvm" ]; then
  # shellcheck disable=SC1091
  source "$HOME/.rvm/scripts/rvm"
  rvm use "$RUBY_VERSION" >/dev/null
elif [ -d "$HOME/.rbenv/shims" ]; then
  export PATH="$HOME/.rbenv/shims:$PATH"
fi

# Peer tools wordmove-ng shells out to (ssh, rsync, mysqldump, wp, ...).
export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
export LC_ALL="${LC_ALL:-C.UTF-8}"

command -v wordmove-ng >/dev/null || { echo "wordmove-ng not found in PATH" >&2; exit 2; }

mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S).log"
LOCK_FILE="${LOCK_FILE:-${TMPDIR:-/tmp}/wordmove-${ENVIRONMENT}.lock}"

cd "$SITE_DIR"

# Refuse to start while a previous run is still active.
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "$(date '+%F %T') previous run still active, skipping" >>"$LOG"
  exit 0
fi

# The output is coloured regardless of TTY; strip the escape codes for the log.
# shellcheck disable=SC2086  # COMPONENTS is a list of flags on purpose
{
  echo "== $(date '+%F %T') wordmove-ng $ACTION -e $ENVIRONMENT $COMPONENTS"
  wordmove-ng "$ACTION" -e "$ENVIRONMENT" $COMPONENTS
  echo "== $(date '+%F %T') finished, exit 0"
} 2>&1 | sed 's/\x1b\[[0-9;]*m//g' >>"$LOG"

# Rotate logs: keep the newest KEEP_LOGS files for this environment.
find "$LOG_DIR" -maxdepth 1 -name "${ENVIRONMENT}-*.log" -printf '%T@ %p\n' \
  | sort -rn | tail -n +"$((KEEP_LOGS + 1))" | cut -d' ' -f2- | xargs -r rm -f
