---
title: Multiple environments
nav_order: 9
---

# Multiple environments

`local` is always your development environment and must keep that name. Every other first level key of `movefile.yml`, at the same indentation level, declares a remote. Here two remotes, `test` and `live`:

```yaml
local:
  vhost: "http://site.test"
  wordpress_path: "/Users/me/Sites/site"
  database:
    ...

test:
  vhost: "https://test.site.net"
  wordpress_path: "/srv/test/www"
  database:
    ...
  ssh:
    ...

live:
  vhost: "https://site.net"
  wordpress_path: "/srv/live/www"
  database:
    ...
  ssh:
    ...
```

Pick the remote with `-e`. With a single remote it is used by default and `-e` can be omitted; with several, omitting it is an error.

- `pull` always lands in `local`; `-e` names where the data comes from: `wordmove-ng pull -t -e live` copies themes from `live` to `local`.
- `push` always starts from `local`; `-e` names the destination: `wordmove-ng push -t -e test` copies themes from `local` to `test`.

You cannot sync two remotes directly; go through `local`.

## Backups per environment

Before a database import the target's database is saved locally, named after the target: `wp-content/local-backup-<timestamp>.sql.gz` on a pull, `wp-content/live-backup-<timestamp>.sql.gz` or `wp-content/test-backup-<timestamp>.sql.gz` on a push.

## Protecting an environment

Use `forbid` to make some operations impossible on a given remote regardless of flags, typically the production database:

```yaml
live:
  forbid:
    push:
      db: true
      uploads: true
```

## Sharing configuration between remotes

Use YAML anchors under `global` to avoid repeating blocks; see [Configuration]({{ site.baseurl }}/configuration/#yaml-and-erb-tips).

## Distinct values

Keep each environment's `vhost` and `wordpress_path` distinct and never a prefix of another's (`https://site.net` versus `https://site.net.staging`), otherwise the search-replace of the shorter value rewrites the longer one. `wordmove-ng doctor` reports such collisions.

Thanks to **@charmcat**, who shared her troubleshooting with the original authors and suggested this page.
