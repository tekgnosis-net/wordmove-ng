---
title: Usage and flags
nav_order: 6
---

# Usage and flags
{: .no_toc }

1. TOC
{:toc}

## Commands

```
wordmove-ng --version, -v   # Print the version
wordmove-ng doctor          # Do some local configuration and environment checks
wordmove-ng help [COMMAND]  # Describe available commands or one specific command
wordmove-ng init            # Generates a brand new movefile.yml
wordmove-ng list            # List all environments and vhosts
wordmove-ng pull            # Pulls WP data from remote host to the local machine
wordmove-ng push            # Pushes WP data from local machine to remote host
```

### `init`
{: .no_toc }

Writes `movefile.yml` in the current directory, reading `wp-config.php` for the local database credentials (splitting `DB_HOST` values that carry a port or a socket) and the local URL from `WP_HOME`, `WP_SITEURL` or `wp option get home`.

### `doctor`
{: .no_toc }

Checks, in order: movefile schema (rejecting `ftp` blocks and reporting prefix collisions), local `mysql`/`mysqldump` and a connection with the local credentials, local `wp` presence and freshness, `rsync`, `ssh`, then for each SSH remote a non interactive login followed by a probe for `rsync`, `gzip`, `mysql`/`mariadb`, `mysqldump`/`mariadb-dump` and `wp`. It also warns about `ssh.gateway.password`. Run it before opening an issue and paste the output.

### `list`
{: .no_toc }

Prints every environment with its `vhost`.

### `push` and `pull`
{: .no_toc }

```
Options:
  -w, [--wordpress], [--no-wordpress]
  -u, [--uploads], [--no-uploads]
  -t, [--themes], [--no-themes]
  -p, [--plugins], [--no-plugins]
  -m, [--mu-plugins], [--no-mu-plugins]
  -l, [--languages], [--no-languages]
  -d, [--db], [--no-db]
  -v, [--verbose], [--no-verbose]
  -s, [--simulate], [--no-simulate]
  -e, [--environment=ENVIRONMENT]
  -c, [--config=CONFIG]
      [--debug], [--no-debug]
      [--no-adapt], [--no-no-adapt]
      [--all], [--no-all]
```

`pull` copies from the remote given with `-e` to `local`; `push` copies from `local` to that remote. At least one component flag (or `--all`) is required.

## Flags

| Flag | Meaning |
| --- | --- |
| `-w`, `--wordpress` | the WordPress core, ignoring `wp-content` |
| `-u`, `--uploads` | `wp-content/uploads` |
| `-t`, `--themes` | `wp-content/themes` |
| `-p`, `--plugins` | `wp-content/plugins` |
| `-m`, `--mu-plugins` | `wp-content/mu-plugins` |
| `-l`, `--languages` | `wp-content/languages` |
| `-d`, `--db` | the database; see [Database sync]({{ site.baseurl }}/database-sync/) |
| `--all` | every component; combine with `--no-*` to leave some out |
| `--no-<component>` | exclude one component, usually with `--all` |
| `-s`, `--simulate` | rsync runs with `--dry-run`; database steps are logged and skipped |
| `-e ENV`, `--environment` | which remote to use; optional with a single remote |
| `-c FILE`, `--config` | alternate movefile inside the project |
| `--no-adapt` | import the database without running `wp search-replace` |
| `-v`, `--verbose` | more output |
| `--debug` | accepted for compatibility; had an effect only with the removed FTP deployer |

Component paths respect the `paths` section of each environment.

## Examples

```bash
wordmove-ng pull -e staging --all              # everything from staging
wordmove-ng push -e production --all --no-db   # every folder, keep the production database
wordmove-ng push -e production --all --no-db --no-uploads
wordmove-ng push -e production -t -p -s        # dry run of themes and plugins
wordmove-ng pull -e production -d --no-adapt   # database without URL rewriting
wordmove-ng push -c movefile.client.yml -e live -u
WORDMOVE_MAINTENANCE_MODE=1 wordmove-ng push -e production -d
```

## Mirroring

File sync mirrors the source: files missing at the source are **deleted** at the destination. Use `exclude` for anything that must survive on one side only (uploads produced on production, `.env` files, caches).

## Work only on specific plugins or themes

`-p` considers the whole `plugins` folder. rsync patterns starting with `+ ` are inclusions, so you can exclude everything but one plugin:

```yaml
exclude:
  - "+ wp-content/plugins/plugin_1/"
  - "wp-content/plugins/*"
```

The same works for themes and any other folder.

## Rsync options in a continuous delivery context

The default rsync flags are `-rlpt`. On a CI runner every file is freshly checked out, so `--times` triggers a full transfer every time and `--perms` may not be what you want:

```yaml
ssh:
  rsync_options: "--itemize-changes --chmod=D775,F664 --no-perms --no-times --checksum"
```

`--no-perms` and `--no-times` disable the defaults, `--checksum` compares content instead of timestamps (slower, but transfers only real changes), and `--chmod` gives you control over what lands on the server.

## Logging

Long generated shell scripts are summarised into intent lines such as `dump database my_db to ./wp-content/dump.sql`, `compress ./wp-content/dump.sql`, `wp search-replace old.test -> new.test in /var/www/site` and `import SQL dump … (strip sandbox header, append COMMIT)`. Passwords, hosts, vhosts and paths from the movefile are masked as `[secret]` in all output, including hook output.
