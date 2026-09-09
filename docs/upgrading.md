---
title: Upgrading from 5.x
nav_order: 4
---

# Upgrading from wordmove 5.x
{: .no_toc }

This applies to both the original `wordmove` gem by weLaika and the kokiddp fork. Your `movefile.yml` keeps working with the exceptions below.

1. TOC
{:toc}

## 1. Install the new gem, use the new command

```bash
gem install wordmove-ng
```

Call `wordmove-ng` instead of `wordmove`. Both gems can stay installed side by side; the executable was renamed on purpose, because both tools read the same `movefile.yml` while their push semantics differ.

## 2. Ruby 3.0 or newer

Ruby 2.6 and 2.7 are no longer supported. See [Installation]({{ site.baseurl }}/installation/#ruby).

## 3. Put `wp` on your remotes

`push -d` now adapts the database **on the remote**, so WP-CLI must be installed there and be in the `$PATH` of a non interactive login. It is a single PHAR file ([installing WP-CLI](https://wp-cli.org/#installing)). Run `wordmove-ng doctor` to confirm; a push refuses to start until it is found.

## 4. FTP and SFTP are gone

A movefile with an `ftp` block fails with a clear error. FTP only ever existed for shell-less shared hosts, where the database had to be handled by uploading temporary PHP scripts and URLs were rewritten in the dump with a regex. Keep the legacy `wordmove` 5.x gem for such hosts, or move them to SSH.

## 5. `global.sql_adapter` is ignored

URL and path adaptation always uses `wp search-replace` on the target; the regex-based `default` adapter no longer exists. The key is still accepted, with a warning, so old movefiles validate. Remove it when convenient. `database.charset`, removed in 3.0, is no longer accepted by the schema either. The `global` section is now optional.

## 6. Push no longer touches your local database

Old versions ran `wp search-replace` on the live local database during a push and restored it afterwards, which left the local site pointing at production if anything failed in between. That is gone: the local database is dumped, and the dump is adapted after import on the remote.

## 7. SSH behaves like rsync did

If rsync worked but the database step asked for a password, the cause was the old Net::SSH library, which could not sign RSA keys with SHA-2 and silently fell back to a prompt. That code path no longer exists: everything uses the system `ssh` client. If key authentication fails now, you get an error naming the failed command instead of a prompt. `ssh.gateway` is passed as `ssh -J`; `ssh.gateway.password` cannot be honoured and is ignored.

## 8. Remote programs are checked up front

Missing `gzip`, `mysql`, `mysqldump` or `wp` on either side aborts before any backup or dump, listing what is missing.

## 9. New, optional: maintenance mode

`global.maintenance_mode: true` wraps the target's import and search-replace in `wp maintenance-mode activate` / `deactivate`. See [Database sync]({{ site.baseurl }}/database-sync/#maintenance-mode).

## Checklist

```bash
gem install wordmove-ng
sed -i '/sql_adapter/d' movefile.yml     # optional tidy-up
wordmove-ng doctor                        # fix anything it reports
wordmove-ng push -e production -d -s      # dry run
```
