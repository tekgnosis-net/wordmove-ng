---
title: Configuration
nav_order: 5
---

# Configuration
{: .no_toc }

`movefile.yml` describes your local install and every remote. It is a YAML file, evaluated as an ERB template first, so it can read environment variables.

1. TOC
{:toc}

## File name and location

wordmove-ng looks for `movefile.yml`, `movefile.yaml`, `movefile` or `Movefile` in the current directory and then in each parent up to the one containing `wp-config.php`. `-c other.yml` selects another file inside the project.

{: .note }
Indentation defines the structure. Two spaces per level, no tabs. `wordmove-ng doctor` validates the file against a schema and tells you what is wrong.

## Complete example

```yaml
global:
  maintenance_mode: false

local:
  vhost: http://site.test
  wordpress_path: /home/john/sites/site
  database:
    name: site
    user: root
    password: root
    host: 127.0.0.1
    # port: 3306
    # socket: /path/to/mysqld.sock

staging:
  vhost: https://staging.example.com
  wordpress_path: /var/www/staging
  database:
    name: staging
    user: staging
    password: "<%= ENV['STAGING_DB_PASS'] %>"
    host: localhost
  ssh:
    host: staging.example.com
    user: deploy
  exclude:
    - ".git/"
    - ".env"
    - "node_modules/"
    - "wp-config.php"
    - "wp-content/*.sql.gz"

production:
  vhost: https://example.com
  wordpress_path: /var/www/example
  database:
    name: example
    user: example
    password: "<%= ENV['PROD_DB_PASS'] %>"
    host: localhost
    # mysqldump_options: --max_allowed_packet=50MB
    # mysql_options: --protocol=TCP
  ssh:
    host: example.com
    user: deploy
    # port: 22
    # password: only with sshpass installed; prefer keys
    # rsync_options: --verbose
    # gateway:
    #   host: bastion.example.com
    #   user: jump
  exclude:
    - ".git/"
    - ".env"
    - "node_modules/"
    - "wp-config.php"
    - "wp-content/*.sql.gz"
  forbid:
    push:
      db: true            # never push the database to production
  hooks:
    push:
      after:
        - command: wp cache flush
          where: remote
          raise: false
```

## First level keys

`local` is mandatory and must keep that name. `global` is optional. Every other first level key is a remote environment, selected with `-e`. See [Multiple environments]({{ site.baseurl }}/environments/).

## `global`

| Key | Default | Meaning |
| --- | --- | --- |
| `maintenance_mode` | `false` | Wrap the target's database import and adaptation in `wp maintenance-mode activate`/`deactivate`. `WORDMOVE_MAINTENANCE_MODE=1` in the environment forces it on for one run. |
| `collation_fallbacks` | built-in table | Collations rewritten before import, e.g. `utf8mb3_uca1400_ai_ci: utf8mb4_unicode_ci`. Setting the key replaces the default table. |
| `charset_fallbacks` | `utf8mb3: utf8mb4` | Charsets rewritten before import. |
| `sql_adapter` | ignored | Accepted with a warning for 5.x movefiles. |

## `local` and each remote

### `vhost`
{: .no_toc }

> mandatory

The URL you use to reach the site, including any subdirectory WordPress is installed in. It should match `wp option get home`. Omit the trailing slash. `init` pre-fills it from `wp-config.php` or `wp option get home`.

### `wordpress_path`
{: .no_toc }

> mandatory

The absolute path of the installation. Spaces and other shell characters are handled; no manual escaping. On a remote it is the path **on that host**.

{: .warning }
Avoid values where one environment's `vhost` or `wordpress_path` is a prefix of another's (`https://site.test` and `https://site.test.example.com`): the search-replace of the shorter value would also rewrite the longer one. The doctor reports this.

### `database`
{: .no_toc }

> mandatory keys: `name`, `user`, `password`, `host`

| Key | Meaning |
| --- | --- |
| `name`, `user`, `password`, `host` | as in `wp-config.php`. For a remote, as seen **from the remote host**: wordmove-ng connects over SSH first and runs `mysqldump`/`mysql`/`wp` there. |
| `port` | optional; `init` splits `DB_HOST` values like `localhost:3307`. |
| `socket` | optional unix socket; `init` splits `DB_HOST` values like `localhost:/path/mysqld.sock`. |
| `mysqldump_options` | passed verbatim to `mysqldump`/`mariadb-dump`, e.g. `--max_allowed_packet=50MB --ignore-table=db.wp_bigtable`. |
| `mysql_options` | passed verbatim to `mysql`/`mariadb` on import, e.g. `--protocol=TCP`. |

`mariadb`/`mariadb-dump` are preferred when installed, falling back to `mysql`/`mysqldump`. Imports run with `--binary-mode` (unless `mysql_options` already sets it), `SET FOREIGN_KEY_CHECKS=0` and a trailing `COMMIT;`; a MariaDB sandbox header is stripped.

### `paths`
{: .no_toc }

> optional

Customise WordPress internal paths when they are not the defaults, relative to `wordpress_path`. Configure it on every environment whose layout differs.

```yaml
paths:
  wp_content: app
  wp_config: config/wp-config.php
  uploads: app/uploads
  plugins: app/plugins
  mu_plugins: app/mu-plugins
  themes: app/themes
  languages: app/languages
```

## Remote-only keys

### `ssh`
{: .no_toc }

> mandatory key: `host`

```yaml
ssh:
  host: host
  user: user
  port: 22                    # optional
  password: secret            # optional; needs sshpass, prefer keys
  rsync_options: "--verbose"  # optional, appended to rsync
  gateway:                    # optional jump host, becomes `ssh -J`
    host: bastion
    user: jump
    port: 22
```

Every operation uses the **system `ssh` client**: rsync for directories, `ssh` for remote commands and hooks, `scp` for dump files. Whatever works for `ssh` on your command line works here: ssh-agent, `~/.ssh/config`, `ProxyJump`, hardware keys, modern key types. Only `host` is mandatory because the rest can live in `~/.ssh/config`:

```
Host client_x_staging
  Hostname 79.99.8.94
  User welaika
  Port 1337
  ProxyJump bastion
```

```yaml
staging:
  ssh:
    host: client_x_staging
```

- Without `password`, connections run with `BatchMode=yes`: a failing key authentication is an error naming the failed command, never a prompt.
- `password` is passed through `sshpass -p` to `ssh`, `scp` and `rsync`. It requires `sshpass` locally and exposes the password in the process list.
- `rsync_options` are appended to the defaults `-rlpt --compress --omit-dir-times --delete`. See [rsync options for CI]({{ site.baseurl }}/usage/#rsync-options-in-a-continuous-delivery-context).
- `gateway` becomes `ssh -J [user@]host[:port]`. A `gateway.password` cannot be honoured and is ignored; the doctor warns.
- Remote commands always run through `sh -c`, so the remote login shell can be bash, zsh, fish or csh. Programs only need to be in the `$PATH` of a non interactive login.

### `exclude`
{: .no_toc }

> optional

Patterns ignored during `push` and `pull`, which also means matching files are **not deleted** on the destination when missing at the source. Each entry becomes an rsync `--exclude`, relative to `wordpress_path`, so all rsync pattern syntax applies; see [working on specific plugins]({{ site.baseurl }}/usage/#work-only-on-specific-plugins-or-themes).

```yaml
exclude:
  - ".git/"
  - ".gitignore"
  - ".env"
  - "node_modules/"
  - "tmp/*"
  - "movefile.yml"
  - "wp-config.php"
  - "wp-content/*.sql.gz"
```

### `hooks`
{: .no_toc }

> optional

Commands run before or after a push or pull, locally or on the remote. See [Hooks]({{ site.baseurl }}/hooks/).

### `forbid`
{: .no_toc }

> optional

Blocks actions by configuration; forbidden tasks ignore command line flags and are skipped with a warning. Values must be booleans.

```yaml
forbid:
  push:
    db: true
    uploads: false
    plugins: false
    themes: false
    languages: false
    mu_plugins: false
  pull:
    db: false
```

### Removed: `ftp`
{: .no_toc }

FTP, FTPS and SFTP transports were removed in 6.0. A remote with an `ftp` block fails validation with a clear message. See [Upgrading]({{ site.baseurl }}/upgrading/#4-ftp-and-sftp-are-gone).

## Environment variables and `.env`

Because the movefile is an ERB template, secrets can come from the environment:

```yaml
production:
  database:
    user: "<%= ENV['PROD_DB_USER'] %>"
    password: "<%= ENV['PROD_DB_PASS'] %>"
```

Set them in the shell (`export PROD_DB_PASS="…"`) or in a `.env` file next to the movefile:

```bash
PROD_DB_USER="username"
PROD_DB_PASS="password"
```

`.env.<environment>` (for example `.env.production`) is loaded when that environment is selected with `-e`. Add `.env*` to `exclude` and to `.gitignore`.

System variables work too: `wordpress_path: "<%= ENV['HOME'] %>/sites/example"`.

## YAML and ERB tips

### Anchors to avoid repetition
{: .no_toc }

```yaml
global:
  default: &default
    vhost: "http://example.com"
    wordpress_path: "/var/www/site"
    database: &db
      host: localhost
      user: username
      password: password
      name: database
    ssh: &ssh
      host: server
      user: foo

staging:
  <<: *default
  vhost: http://staging.example.com
  database:
    <<: *db
    name: db_staging
  ssh:
    <<: *ssh
    user: foobar

production:
  <<: *default
  vhost: https://www.example.com
  database:
    <<: *db
    name: db_production
```

The `default` anchor lives under `global` because every other first level key is treated as an environment.

### Variables inside the template
{: .no_toc }

```yaml
production:
  <% prod_wp_path = "/home/site/public" %>
  vhost: "https://example.com"
  wordpress_path: <%= prod_wp_path %>
  hooks:
    pull:
      after:
        - command: 'cd <%= prod_wp_path %> && wp core version'
          where: remote
```

### Conditional sections
{: .no_toc }

```yaml
  hooks:
    pull:
      after:
        <% if ENV.fetch('NOTIFY', nil) %>
        - command: 'bash ./scripts/notify.sh'
          where: local
        <% end %>
        - command: 'wp cache flush'
          where: remote
```

`ENV.fetch('NOTIFY', nil)` returns the variable or `nil`; you can also compare against values (`<% if ENV.fetch('TARGET', '') == 'blue' %>`).

## Schema validation

`wordmove-ng doctor` validates every section against the schemas in [`lib/wordmove/assets`](https://github.com/tekgnosis-net/wordmove-ng/tree/master/lib/wordmove/assets), reports unknown or mistyped keys, rejects `ftp` blocks and flags prefix collisions between search terms.
