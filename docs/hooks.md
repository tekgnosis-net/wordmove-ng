---
title: Hooks
nav_order: 8
---

# Hooks
{: .no_toc }

Hooks run arbitrary commands before or after a `push` or `pull`, locally or on the remote.

1. TOC
{:toc}

## Syntax

```yaml
production:
  hooks:
    push:
      before:
        - command: 'echo "do something"'
          where: local
          raise: false        # raise is true by default
      after:
        - command: 'echo "do something"'
          where: remote
    pull:
      before:
        - command: 'echo "do something"'
          where: local
      after:
        - command: 'echo "do something"'
          where: remote
```

- `hooks` is optional and is configured per remote environment, never under `local`.
- Two groups, `push` and `pull`, each with `before` and `after`, each a sequence of command objects.
- `command`: the command to run. Quote it, preferably with single quotes, since double quotes are often used inside commands.
- `where`: `local` or `remote`. `remote` is always the environment given with `-e`, or the only remote when there is one.
- `raise`: default `true`. With `false`, a failing command (exit status > 0) is logged and the operation continues.

Hooks run regardless of which components you selected: `push --all` and `push -t` trigger the same hooks. `wordmove-ng doctor` validates them.

## Execution

- Both local and remote hooks run inside the respective `wordpress_path`. Change directory inside the command if needed: `cd tools && ./build.sh`.
- Hooks run in order, synchronously. What you read is what you get.
- Remote hooks use the same `ssh` settings as everything else (host, user, port, password, gateway) through the system `ssh` binary, and run inside `sh -c`, so the remote login shell does not matter. Programs must be in the `$PATH` of a non interactive login; if `wp` is not found, add its directory to `PATH` in `~/.bashrc` or `~/.profile` on the remote, or use an absolute path.
- Hook output is logged with movefile secrets masked as `[secret]`.

## Error handling

```yaml
hooks:
  push:
    before:
      - command: 'exit 1'
        where: remote
        raise: false
      - command: 'echo "Still working"'
        where: local
```

The first command fails, the second still runs, and since these are before-push hooks the push happens too. The error is visible in the log. Without `raise: false` the failure stops everything.

## Examples

```yaml
hooks:
  push:
    before:
      - command: 'npm run build'                       # build assets before pushing
        where: local
      - command: 'rm -rf ./tmp/*'
        where: local
    after:
      - command: 'wp rewrite flush'
        where: remote
      - command: 'wp cache flush'
        where: remote
      - command: 'wp option set blog_public 0'         # keep staging out of search engines
        where: remote
      - command: 'find . -type f -exec chmod 664 {} +'  # fix permissions
        where: remote
      - command: 'find . -type d -exec chmod 755 {} +'
        where: remote
      - command: 'bash ./scripts/notify.sh'            # tell the team
        where: local
        raise: false
  pull:
    after:
      - command: 'wp option update siteurl http://site.test'
        where: local
      - command: 'wp plugin deactivate wordfence'       # no security plugin locally
        where: local
        raise: false
```

Maintenance mode around the database replacement is built in (`global.maintenance_mode`), so hooks are not needed for that.

## ERB inside hooks

Because the movefile is an ERB template, hooks can be conditional or share variables with the rest of the file. See [Configuration]({{ site.baseurl }}/configuration/#yaml-and-erb-tips).
