---
title: Quick start
nav_order: 3
---

# Quick start
{: .no_toc }

1. TOC
{:toc}

## 1. Create the movefile

Run `init` from the directory that contains `wp-config.php`:

```bash
cd /path/to/your/wordpress
wordmove-ng init
```

It writes `movefile.yml`, pre-filled with the local database credentials, socket or port from `wp-config.php` and the local URL from `WP_HOME`/`WP_SITEURL` or `wp option get home`. Open the file and fill in the `production` section (rename it as you like): the remote `vhost`, `wordpress_path`, database credentials **as seen from the remote host**, and the `ssh` block.

```yaml
production:
  vhost: https://example.com
  wordpress_path: /var/www/example
  database:
    name: example
    user: example
    password: "<%= ENV['PROD_DB_PASS'] %>"
    host: localhost
  ssh:
    host: example.com
    user: deploy
```

The full reference is in [Configuration]({{ site.baseurl }}/configuration/).

## 2. Check everything

```bash
wordmove-ng doctor
```

The doctor validates the movefile, checks the local tools and database connection, then for each SSH remote tries a non interactive login and probes for `rsync`, `gzip`, `mysql`, `mysqldump` and `wp`. Fix what it reports before going on.

## 3. Pull the site down

```bash
wordmove-ng pull -e production --all
```

Files are mirrored into your local install, the remote database is dumped, imported locally and rewritten to your local URL and path. Your previous local database is saved as `wp-content/local-backup-<timestamp>.sql.gz` first.

## 4. Push changes up

Simulate first: `-s` runs rsync with `--dry-run` and skips the database steps after logging what would happen.

```bash
wordmove-ng push -e production -t -p -s     # themes and plugins, dry run
wordmove-ng push -e production -t -p        # for real
wordmove-ng push -e production -d           # database only
```

A push of the database backs up the remote database to `wp-content/production-backup-<timestamp>.sql.gz` locally, dumps your local database, imports it on the remote and runs `wp search-replace` there. Your local database is never modified.

## Everyday commands

| Command | Effect |
| --- | --- |
| `wordmove-ng pull -e staging -u` | fetch the uploads folder from staging |
| `wordmove-ng push -e production --all --no-db` | mirror every folder, keep the production database |
| `wordmove-ng push -e production --all --no-uploads` | everything but uploads |
| `wordmove-ng pull -e production -d --no-adapt` | import the production database without rewriting URLs |
| `wordmove-ng list` | show every environment and its vhost |
| `wordmove-ng help push` | all flags |

With a single remote environment `-e` can be omitted. Every flag is explained in [Usage and flags]({{ site.baseurl }}/usage/).

{: .warning }
File sync **mirrors** the source: files missing at the source are deleted at the destination. Anything you need to keep on one side only goes in `exclude`.
