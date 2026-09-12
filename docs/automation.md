---
title: Automation and cron
nav_order: 10
---

# Automation and cron
{: .no_toc }

wordmove-ng never prompts, so it runs unattended: from cron, systemd timers, CI runners or deploy scripts. What differs from an interactive shell is the environment, and this page covers exactly that.

1. TOC
{:toc}

## What cron does not give you

- **No version manager.** rvm and rbenv shims are loaded by your shell profile, which cron does not read. `ruby`, `gem` executables and the gemset must be made visible explicitly.
- **No ssh-agent.** There is no agent socket, so the SSH key must be usable without one: a key without a passphrase, or a key held by a system agent you start yourself.
- **A minimal `PATH`.** `rsync`, `mysqldump`, `wp` and friends installed under `~/bin`, `/usr/local/bin` or a MAMP/Local directory are not found unless you add them.
- **No TTY.** Output is still coloured; strip the escape codes when logging to a file.

`wordmove-ng` itself is already safe here: SSH runs with `BatchMode=yes`, a failing key authentication is an error rather than a hanging prompt, prerequisites are checked before any side effect, and every failure exits non-zero.

## Prepare once

### A key cron can use
{: .no_toc }

Create a dedicated key without a passphrase and restrict what it can do on the server:

```bash
ssh-keygen -t ed25519 -N '' -f ~/.ssh/wordmove_cron_ed25519 -C wordmove-cron
```

In the remote `~/.ssh/authorized_keys`, prefix the public key with restrictions:

```
from="203.0.113.10",no-port-forwarding,no-X11-forwarding,no-agent-forwarding ssh-ed25519 AAAA… wordmove-cron
```

Then point the movefile at a `~/.ssh/config` entry that names the key, so the movefile stays free of machine-specific paths:

```
Host prod-wordmove
  Hostname example.com
  User deploy
  IdentityFile ~/.ssh/wordmove_cron_ed25519
  IdentitiesOnly yes
```

```yaml
production:
  ssh:
    host: prod-wordmove
```

### Secrets in `.env`
{: .no_toc }

Keep database passwords in a `.env` file next to `movefile.yml` with mode `600`, referenced as `<%= ENV['PROD_DB_PASS'] %>`. Never put them in the crontab, which is readable by other means and shows up in logs.

### Guard rails in the movefile
{: .no_toc }

A scheduled job should not be able to do more than it was written for, even if the script is edited later. Use `forbid`:

```yaml
production:
  forbid:
    push:
      db: true          # a file-sync job must never push the database
      uploads: true
```

and `exclude` for anything that lives on one side only, because syncs **mirror** the source: a scheduled `pull --all` overwrites local changes, a scheduled `push --all` overwrites uploads added through the WordPress admin since the last run.

## The script

The repository ships [`contrib/wordmove-sync.sh`](https://github.com/tekgnosis-net/wordmove-ng/blob/master/contrib/wordmove-sync.sh). Copy it to `/usr/local/bin/`, adjust the settings block at the top or override the variables from the environment. It

- loads rvm (`RUBY_VERSION=ruby-3.4.9`) or rbenv, and extends `PATH` for the peer tools;
- refuses to start while a previous run holds the lock, so overlapping runs cannot happen;
- writes one plain-text log per run to `~/log/wordmove/` with colour codes stripped, and keeps the last 30;
- exits non-zero when the sync fails, so cron mails you when `MAILTO` is set.

```bash
#!/usr/bin/env bash
set -euo pipefail

SITE_DIR="${SITE_DIR:-/path/to/wordpress}"        # directory holding movefile.yml
ENVIRONMENT="${ENVIRONMENT:-production}"
ACTION="${ACTION:-pull}"                          # pull or push
COMPONENTS="${COMPONENTS:---all --no-db}"
LOG_DIR="${LOG_DIR:-$HOME/log/wordmove}"
RUBY_VERSION="${RUBY_VERSION:-}"                  # e.g. ruby-3.4.9 for rvm

if [ -n "$RUBY_VERSION" ] && [ -s "$HOME/.rvm/scripts/rvm" ]; then
  source "$HOME/.rvm/scripts/rvm"; rvm use "$RUBY_VERSION" >/dev/null
elif [ -d "$HOME/.rbenv/shims" ]; then
  export PATH="$HOME/.rbenv/shims:$PATH"
fi
export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S).log"
cd "$SITE_DIR"

exec 9>"/tmp/wordmove-${ENVIRONMENT}.lock"
flock -n 9 || { echo "$(date '+%F %T') previous run still active" >>"$LOG"; exit 0; }

{
  echo "== $(date '+%F %T') wordmove-ng $ACTION -e $ENVIRONMENT $COMPONENTS"
  wordmove-ng "$ACTION" -e "$ENVIRONMENT" $COMPONENTS
  echo "== $(date '+%F %T') finished"
} 2>&1 | sed 's/\x1b\[[0-9;]*m//g' >>"$LOG"
```

(abridged; the shipped file adds validation and log rotation)

## Crontab

Nightly at 02:30 local time, with failures mailed to you:

```
MAILTO=you@example.com
30 2 * * * SITE_DIR=/home/me/sites/example RUBY_VERSION=ruby-3.4.9 /usr/local/bin/wordmove-sync.sh
```

Several sites or environments are just several lines with different variables. Stagger them so their windows do not overlap on the same remote.

## Test it the way cron runs it

A missing `PATH` entry or an unreadable key only shows up under cron's empty environment, so reproduce that before trusting the schedule:

```bash
env -i HOME=$HOME SHELL=/bin/bash PATH=/usr/bin:/bin \
  SITE_DIR=/home/me/sites/example RUBY_VERSION=ruby-3.4.9 /usr/local/bin/wordmove-sync.sh
echo "exit $?"
tail -n 40 ~/log/wordmove/production-*.log
```

Running `wordmove-ng doctor` under the same `env -i` prefix is the quickest check that the key and every tool resolve without an agent.

## Database jobs

For a scheduled database push enable `global.maintenance_mode` so the seconds between import and `wp search-replace` show visitors the maintenance page instead of the wrong URLs. Scheduled database pulls are the common case (a nightly copy of production for development) and need nothing special; each run leaves a `local-backup-<timestamp>.sql.gz` in `wp-content/`, so prune those occasionally.

## systemd timer instead of cron

The same script works as a `oneshot` service:

```ini
# ~/.config/systemd/user/wordmove-sync.service
[Service]
Type=oneshot
Environment=SITE_DIR=/home/me/sites/example RUBY_VERSION=ruby-3.4.9
ExecStart=/usr/local/bin/wordmove-sync.sh

# ~/.config/systemd/user/wordmove-sync.timer
[Timer]
OnCalendar=*-*-* 02:30:00
Persistent=true
[Install]
WantedBy=timers.target
```

`systemctl --user enable --now wordmove-sync.timer`, and `journalctl --user -u wordmove-sync` for the output. Enable lingering (`loginctl enable-linger $USER`) so user timers run without a login session.
