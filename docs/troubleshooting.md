---
title: Troubleshooting
nav_order: 11
---

# Troubleshooting and FAQ
{: .no_toc }

Start with `wordmove-ng doctor`: it reproduces most problems below and names the failing command.

1. TOC
{:toc}

## SSH

### Non interactive SSH authentication failed
{: .no_toc }

wordmove-ng runs `ssh` with `BatchMode=yes` when no `ssh.password` is configured, so it never prompts. The doctor prints the exact command, for example `ssh -o BatchMode=yes -p 22 deploy@example.com true`; run it yourself to see what OpenSSH says. Usual causes: the key is not loaded in the agent (`ssh-add -l`), the host expects a different user, or the key is not in the remote `authorized_keys`. Anything you fix in `~/.ssh/config` applies to wordmove-ng automatically.

### It worked with wordmove 5.x and rsync still works, but the database step asked for a password
{: .no_toc }

That was the old Net::SSH library, which could not sign RSA keys with SHA-2 and silently fell back to a prompt on modern servers. wordmove-ng no longer contains it. See [Upgrading]({{ site.baseurl }}/upgrading/#7-ssh-behaves-like-rsync-did).

### Gateway / jump host
{: .no_toc }

`ssh.gateway` is passed as `ssh -J`; the bastion must accept your key or agent. `gateway.password` cannot be used. Alternatively configure `ProxyJump` in `~/.ssh/config` and only set `ssh.host`.

### Password authentication
{: .no_toc }

`ssh.password` requires `sshpass` installed locally and exposes the password in the process list. Keys are strongly recommended.

## Missing programs

### `Missing programs required for the database sync (on "production": wp)`
{: .no_toc }

The remote needs `wp` (for push) in the `$PATH` of a **non interactive** login, which usually only reads `~/.bashrc` or `~/.profile`. Check with `ssh host 'command -v wp'`. Install WP-CLI as a PHAR in `~/bin` and add it to `PATH` in one of those files. The same applies to `gzip`, `mysql`/`mariadb` and `mysqldump`/`mariadb-dump`.

### `mysqldump: command not found` locally
{: .no_toc }

Bundled stacks such as MAMP, XAMPP or Local keep the MySQL binaries out of your `PATH`. Find them (`sudo find /Applications -type f -name mysqldump` on macOS) and add the directory to your shell profile:

```bash
echo 'export PATH="/Applications/MAMP/Library/bin:$PATH"' >> ~/.zshrc
```

Reopen the terminal; `wordmove-ng doctor` should now find them.

## Database

### Import fails with a collation or charset error
{: .no_toc }

Newer `utf8mb3` collations are rewritten automatically before import. If your dump uses another collation the target does not know, add it to `global.collation_fallbacks`; see [Database sync]({{ site.baseurl }}/database-sync/#mariadb-and-mysql-compatibility).

### `invalid byte sequence in UTF-8`
{: .no_toc }

wordmove-ng no longer rewrites dumps as text for URL adaptation, so this error from older versions should not occur. Binary or `latin1` data can still upset a transfer between servers with different defaults: add `--hex-blob` to `mysqldump_options` (thanks @360Zen), make sure your columns are `utf8mb4`, and use a UTF-8 locale in your shell (`export LC_ALL=en_US.UTF-8`). Tables of third party plugins can be skipped with `--ignore-table=db.table`.

### `wordmove-ng init` fails with `invalid byte sequence in UTF-8`
{: .no_toc }

Some localized WordPress packages ship a `wp-config-sample.php` encoded in `iso-8859-1`, and people copy it to `wp-config.php`. Convert the file:

```bash
iconv -f ISO-8859-1 -t UTF-8 wp-config.php > wp-config.utf8.php && mv wp-config.utf8.php wp-config.php
```

### The remote site shows my local URLs after a push
{: .no_toc }

The import succeeded but `wp search-replace` on the remote failed; the log names the backup file. Run the search-replace by hand or restore, see [Backups and recovery]({{ site.baseurl }}/database-sync/#backups-and-recovery). Enable `global.maintenance_mode` to hide this window from visitors.

### Different table prefixes
{: .no_toc }

Not supported: local and remote must use the same `$table_prefix`.

### Large databases time out
{: .no_toc }

Raise `max_allowed_packet` and use `--single-transaction --quick` through `mysqldump_options` and `mysql_options`; see [Large databases]({{ site.baseurl }}/database-sync/#large-databases).

## Files

### Files I need were deleted
{: .no_toc }

Sync mirrors the source. Anything that must survive on one side only (uploads created on production, `.env`, caches) belongs in `exclude`. Backups of the database are never deleted by a sync, but add `wp-content/*.sql.gz` to `exclude` so they are not copied either.

### Permissions are wrong on the server
{: .no_toc }

Use `rsync_options: "--chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r"` (or a post-push hook with `find … -exec chmod`) and consider `--no-perms` from a CI runner; see [Usage]({{ site.baseurl }}/usage/#rsync-options-in-a-continuous-delivery-context).

### Security plugins
{: .no_toc }

Plugins such as Wordfence write `.user.ini` and firewall files into the WordPress root that are specific to one host. Exclude them, or deactivate the plugin locally with a pull hook.

## Movefile

### `This remote is configured with ftp`
{: .no_toc }

FTP was removed in 6.0. Move the host to SSH or keep the legacy `wordmove` 5.x gem for it.

### `global.sql_adapter … is ignored`
{: .no_toc }

Harmless leftover from 5.x; delete the key.

### `"…" is a prefix of "…"`
{: .no_toc }

Two of the four search terms overlap; use distinct vhosts and paths, see [Prefix collisions]({{ site.baseurl }}/database-sync/#prefix-collisions).

### YAML errors
{: .no_toc }

Indentation is the structure: two spaces, no tabs. Quote values containing `:` or `#`. The doctor prints the path of the offending key.

## FAQ

**Which transport is used?** SSH only: `rsync -e ssh` for directories, `ssh` for commands and hooks, `scp` for dump files. There is no Ruby-side SSH implementation.

**Is the source database ever modified?** No. It is dumped; the import and the URL rewriting happen on the target.

**Is there a rollback?** Backups of the target database are written to the local `wp-content` before every import; restore them by hand.

**Is it transactional?** No. Prerequisites are checked before anything happens, and each step is logged, but an interruption in the middle can leave a `dump.sql` or `dump.sql.gz` in a `wp-content` folder, or the target with the source's URLs. Re-run the command or restore the backup.

**What is left on my server?** Nothing but the site itself. Temporary dumps are removed after each run.

**Windows?** Through WSL only; see [Installation]({{ site.baseurl }}/installation/#windows).
