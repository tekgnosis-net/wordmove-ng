---
title: Database sync
nav_order: 7
---

# Database sync
{: .no_toc }

1. TOC
{:toc}

## What happens on `-d`

Both directions have the same shape. The **source** database is only ever read.

| Step | `pull -e production -d` | `push -e production -d` |
| --- | --- | --- |
| 1. Prerequisites | probe local for `gzip`, `mysql`, `wp`; remote for `gzip`, `mysqldump` | probe local for `gzip`, `mysqldump`; remote for `gzip`, `mysql`, `wp` |
| 2. Backup the target | local DB to `wp-content/local-backup-<ts>.sql.gz` | remote DB downloaded to `wp-content/production-backup-<ts>.sql.gz` |
| 3. Dump the source | remote `mysqldump`, gzip, `scp` down | local `mysqldump`, normalise collations, gzip, `scp` up |
| 4. Import on the target | `mysql` locally | `mysql` on the remote over SSH |
| 5. Adapt on the target | `wp search-replace` locally for `vhost`, then `wordpress_path` | `wp search-replace` on the remote for `vhost`, then `wordpress_path` |
| 6. Clean up | temp dumps removed | temp dumps removed |

Step 1 aborts with a list of missing programs before anything else happens, so a misconfigured host never leaves a half-done sync.

`wp search-replace` runs with `--all-tables --skip-columns=guid --allow-root`, so every table in the target database is adapted, including non-WordPress tables sharing it, and post GUIDs are left alone as WordPress recommends. wp-cli unserializes PHP data properly, so serialized options, widgets and page-builder data survive. `--no-adapt` skips step 5.

## Backups and recovery

Backups are gzipped SQL files in the local `wp-content/` folder, named after the target environment and a Unix timestamp. To restore one:

```bash
gunzip < wp-content/production-backup-1757400000.sql.gz | mysql -u user -p example      # on the remote
gunzip < wp-content/local-backup-1757400000.sql.gz | mysql -u root -p site            # locally
```

If the remote `wp search-replace` fails after the import, the log names the backup file and the remote is left with the local URLs. Either restore, or re-run `wordmove-ng push -d`, or run the search-replace by hand on the remote:

```bash
wp search-replace 'http://site.test' 'https://example.com' --all-tables --skip-columns=guid --path=/var/www/example
```

Add `wp-content/*.sql.gz` to `exclude` so backups are never synced.

## Maintenance mode

```yaml
global:
  maintenance_mode: true
```

wraps steps 4 and 5 on the target in `wp maintenance-mode activate` and `deactivate`, so visitors see the WordPress maintenance page rather than a site pointing at the other environment's URLs for a few seconds. Deactivation runs even when the adaptation fails. `WORDMOVE_MAINTENANCE_MODE=1` forces it on for a single run. Default: off.

## MariaDB and MySQL compatibility

- `mariadb` and `mariadb-dump` are preferred when present, falling back to `mysql` and `mysqldump`, on each side independently.
- Dumps starting with the MariaDB sandbox header `/*!999999- enable the sandbox mode */` import cleanly on servers that do not understand it.
- Imports run with `--binary-mode`, `SET FOREIGN_KEY_CHECKS=0` and a trailing `COMMIT;`, unless `mysql_options` already sets binary mode.
- `database.socket` and `database.port` are first-class; `--socket` inside `mysql_options` or `mysqldump_options` still works.
- Newer `utf8mb3` collations (`utf8mb3_uca1400_*`, `utf8mb3_unicode_520_ci`) are rewritten to `utf8mb4_unicode_ci`, and `utf8mb3` to `utf8mb4`, before import. Override or extend the mappings:

```yaml
global:
  collation_fallbacks:
    utf8mb3_uca1400_ai_ci: utf8mb4_unicode_ci
  charset_fallbacks:
    utf8mb3: utf8mb4
```

- `wp` is always called with `--allow-root`, so root-owned Docker installs work.

## Large databases

Pass options straight to the dump and import tools:

```yaml
database:
  mysqldump_options: "--max_allowed_packet=1G --single-transaction --quick --ignore-table=example.wp_actionscheduler_logs"
  mysql_options: "--max_allowed_packet=1G"
```

`--hex-blob` in `mysqldump_options` makes binary columns safe to move between servers with different defaults.

## Table prefixes

Local and remote must use the same table prefix. `wp search-replace --all-tables` rewrites values, not table names.

## Prefix collisions

If one of the four search terms (local and remote `vhost` and `wordpress_path`) is a prefix of another, for example `https://site.test` and `https://site.test.example.com`, the replacement of the shorter value also rewrites the longer one. The doctor reports this as an error and the database step warns before running. Use distinct values.
